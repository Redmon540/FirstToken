module admin::nft {
    use std::error;
    use std::signer;
    use std::string::{Self, String};
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::coin;
    // use aptos_framework::aptos_account;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::timestamp;
    // use aptos_std::ed25519;
    use aptos_token::token::{Self, TokenDataId};
    #[test_only]
    use aptos_framework::account::create_account_for_test;

    // This struct stores the token receiver's address and token_data_id in the event of token minting
    struct TokenMintingEvent has drop, store {
        token_receiver_address: address,
        token_data_id: TokenDataId,
    }

    // This struct stores an NFT collection's relevant information
    struct CollectionTokenMinter has key {
        signer_cap: account::SignerCapability,
        token_data_id: TokenDataId,
        expiration_timestamp: u64,
        minting_enabled: bool,
        token_minting_events: EventHandle<TokenMintingEvent>,
    }

    // This struct stores the challenge message that proves that the resource signer wants to mint this token
    // to the receiver. This struct will need to be signed by the resource signer to pass the verification.
    struct MintProofChallenge has drop {
        receiver_account_sequence_number: u64,
        receiver_account_address: address,
        token_data_id: TokenDataId,
    }

    /// Action not authorized because the signer is not the owner of this module
    const ENOT_AUTHORIZED: u64 = 1;
    /// The collection minting is expired
    const ECOLLECTION_EXPIRED: u64 = 2;
    /// The collection minting is disabled
    const EMINTING_DISABLED: u64 = 3;
    /// Specified public key is not the same as the collection token minter's public key
    const EWRONG_PUBLIC_KEY: u64 = 4;
    /// Specified scheme required to proceed with the smart contract operation - can only be ED25519_SCHEME(0) OR MULTI_ED25519_SCHEME(1)
    const EINVALID_SCHEME: u64 = 5;
    /// Specified proof of knowledge required to prove ownership of a public key is invalid
    const EINVALID_PROOF_OF_KNOWLEDGE: u64 = 6;

    /// Initialize this module: create a resource account, a collection, and a token data id
    fun init_module(resource_account: &signer) {
        let collection_name = string::utf8(b"handy meta girl");
        let description = string::utf8(b"this is my test nft.");
        let collection_uri = string::utf8(b"https://nftstorage.link/ipfs/bafybeibmfsh6djprouyriwebsznhb6zde3cg7xaj2x2s7uxprybmotynga");
        let token_name = string::utf8(b"girl");
        let token_uri = string::utf8(b"Token uri");
        let expiration_timestamp = 1000000;

        // create the resource account that we'll use to create tokens
        // let resource_signer_cap = resource_account::retrieve_resource_account_cap(resource_account, @0xcafe);
        let (_resource, resource_signer_cap) = account::create_resource_account(resource_account, b"name");
        let resource_signer = account::create_signer_with_capability(&resource_signer_cap);
        // create the nft collection
        let maximum_supply = 0;
        let mutate_setting = vector<bool>[ false, false, false ];
        let resource_account_address = signer::address_of(&resource_signer);
        token::create_collection(&resource_signer, collection_name, description, collection_uri, maximum_supply, mutate_setting);

        // create a token data id to specify which token will be minted
        let token_data_id = token::create_tokendata(
            &resource_signer,
            collection_name,
            token_name,
            string::utf8(b"this is my first token"),
            0,
            token_uri,
            resource_account_address,
            1,
            0,
            // we don't allow any mutation to the token
            token::create_token_mutability_config(
                &vector<bool>[ false, false, false, false, true ]
            ),
            vector::empty<String>(),
            vector::empty<vector<u8>>(),
            vector::empty<String>(),
        );

        move_to(resource_account, CollectionTokenMinter {
            signer_cap: resource_signer_cap,
            token_data_id,
            expiration_timestamp,
            minting_enabled: true,
            token_minting_events: account::new_event_handle<TokenMintingEvent>(&resource_signer),
        });
    }

    /// Set if minting is enabled for this collection token minter
    public entry fun set_minting_enabled(minter: &signer, minting_enabled: bool) acquires CollectionTokenMinter {
        let minter_address = signer::address_of(minter);
        assert!(minter_address == @admin, error::permission_denied(ENOT_AUTHORIZED));
        let collection_token_minter = borrow_global_mut<CollectionTokenMinter>(minter_address);
        collection_token_minter.minting_enabled = minting_enabled;
    }

    /// Set the expiration timestamp of this collection token minter
    public entry fun set_timestamp(minter: &signer, expiration_timestamp: u64) acquires CollectionTokenMinter {
        let minter_address = signer::address_of(minter);
        assert!(minter_address == @admin, error::permission_denied(ENOT_AUTHORIZED));
        let collection_token_minter = borrow_global_mut<CollectionTokenMinter>(minter_address);
        collection_token_minter.expiration_timestamp = expiration_timestamp;
    }

    public entry fun mint_nft(receiver: &signer, amount:u64) acquires CollectionTokenMinter {
        coin::transfer<0x1::aptos_coin::AptosCoin>(receiver, @admin, amount);
        let receiver_addr = signer::address_of(receiver);

        // get the collection minter and check if the collection minting is disabled or expired
        let collection_token_minter = borrow_global_mut<CollectionTokenMinter>(@admin);
        // Debug(collection_token_minter);
        //assert!(timestamp::now_seconds() < collection_token_minter.expiration_timestamp, error::permission_denied(ECOLLECTION_EXPIRED));
        // assert!(collection_token_minter.minting_enabled, error::permission_denied(EMINTING_DISABLED));

        // mint token to the receiver
        let resource_signer = account::create_signer_with_capability(&collection_token_minter.signer_cap);
        let token_id = token::mint_token(&resource_signer, collection_token_minter.token_data_id, 1);
        token::direct_transfer(&resource_signer, receiver, token_id, 1);

        event::emit_event<TokenMintingEvent>(
            &mut collection_token_minter.token_minting_events,
            TokenMintingEvent {
                token_receiver_address: receiver_addr,
                token_data_id: collection_token_minter.token_data_id,
            }
        );

        // mutate the token properties to update the property version of this token
        let (creator_address, collection, name) = token::get_token_data_id_fields(&collection_token_minter.token_data_id);
        token::mutate_token_properties(
            &resource_signer,
            receiver_addr,
            creator_address,
            collection,
            name,
            0,
            1,
            vector::empty<String>(),
            vector::empty<vector<u8>>(),
            vector::empty<String>(),
        );
    }

    #[test_only]
    struct FakeCoin {}

    #[test_only]
    public fun set_up_test(origin_account: signer, collection_token_minter: &signer, aptos_framework: signer, nft_receiver: &signer, timestamp: u64) {
        // set up global time for testing purpose
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test_secs(timestamp);

        create_account_for_test(signer::address_of(&origin_account));

        // create a resource account from the origin account, mocking the module publishing process
        account::create_resource_account(&origin_account, b"name");

        init_module(collection_token_minter);

        create_account_for_test(signer::address_of(nft_receiver));
        // print(b"helo") ;
        // debug::print(&258698);
    }

    #[test (origin_account = @0xcafe, collection_token_minter = @admin, nft_receiver = @0x123, nft_receiver2 = @0x234, aptos_framework = @aptos_framework)]
    public entry fun test_happy_path(origin_account: signer, collection_token_minter: signer, nft_receiver: signer, nft_receiver2: signer, aptos_framework: signer) acquires CollectionTokenMinter {
       
        set_up_test(origin_account, &collection_token_minter, aptos_framework, &nft_receiver, 10);

        // mint nft to this nft receiver
        mint_nft(&nft_receiver);

        // check that the nft_receiver has the token in their token store
        let collection_token_minter = borrow_global_mut<CollectionTokenMinter>(@admin);
        let resource_signer = account::create_signer_with_capability(&collection_token_minter.signer_cap);
        let token_id = token::create_token_id_raw(signer::address_of(&resource_signer), string::utf8(b"Collection name"), string::utf8(b"Token name"), 1);
        let new_token = token::withdraw_token(&nft_receiver, token_id, 1);

        // put the token back since a token isn't droppable
        token::deposit_token(&nft_receiver, new_token);

        // mint the second NFT
        create_account_for_test(signer::address_of(&nft_receiver2));
        mint_nft(&nft_receiver2);

        //  check the property version is properly updated
        let token_id2 = token::create_token_id_raw(signer::address_of(&resource_signer), string::utf8(b"Collection name"), string::utf8(b"Token name"), 2);
        let new_token2 = token::withdraw_token(&nft_receiver2, token_id2, 1);
        token::deposit_token(&nft_receiver2, new_token2);
    }

    #[test (origin_account = @0xcafe, collection_token_minter = @0x9b2a708467f204a30d36a81ecde5c61b14735667cda37d35d11e0c575aba4066, nft_receiver = @0x123, aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 327682)]
    public entry fun test_minting_expired(origin_account: signer, collection_token_minter: signer, nft_receiver: signer, aptos_framework: signer) acquires CollectionTokenMinter {
        set_up_test(origin_account, &collection_token_minter, aptos_framework, &nft_receiver, 10000000);
        mint_nft(&nft_receiver);
    }

    #[test (origin_account = @0xcafe, collection_token_minter = @0x9b2a708467f204a30d36a81ecde5c61b14735667cda37d35d11e0c575aba4066, nft_receiver = @0x123, aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 327682)]
    public entry fun test_update_expiration_time(origin_account: signer, collection_token_minter: signer, nft_receiver: signer, aptos_framework: signer) acquires CollectionTokenMinter {
        set_up_test(origin_account, &collection_token_minter, aptos_framework, &nft_receiver, 10);
        // set the expiration time of the minting to be earlier than the current time
        set_timestamp(&collection_token_minter, 5);
        mint_nft(&nft_receiver);
    }

    #[test (origin_account = @0xcafe, collection_token_minter = @0x9b2a708467f204a30d36a81ecde5c61b14735667cda37d35d11e0c575aba4066, nft_receiver = @0x123, aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 327683)]
    public entry fun test_update_minting_enabled(origin_account: signer, collection_token_minter: signer, nft_receiver: signer, aptos_framework: signer) acquires CollectionTokenMinter {
        set_up_test(origin_account, &collection_token_minter, aptos_framework, &nft_receiver, 10);
        // disable token minting
        set_minting_enabled(&collection_token_minter, false);
        mint_nft(&nft_receiver);
    }
}
