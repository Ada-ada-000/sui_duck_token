module duck_token::duck_token {
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::coin_registry;

    /// One-time witness required by Sui `init` convention.
    public struct DUCK_TOKEN has drop {}

    /// Called automatically on package publish.
    fun init(_otw: DUCK_TOKEN, ctx: &mut sui::tx_context::TxContext) {
        let (builder, treasury_cap) = coin_registry::new_currency_with_otw(
            _otw,
            9,
            b"DUCK".to_string(),
            b"Decentral Universal Credit Kernel".to_string(),
            b"Decentralized universal credit kernel, on-chain credit, cross-chain settlement.".to_string(),
            b"".to_string(),
            ctx,
        );
        coin_registry::finalize_and_delete_metadata_cap(builder, ctx);

        sui::transfer::public_transfer(treasury_cap, sui::tx_context::sender(ctx));
    }

    /// Mint DUCK to recipient.
    public fun mint(
        treasury_cap: &mut TreasuryCap<DUCK_TOKEN>,
        amount: u64,
        recipient: address,
        ctx: &mut sui::tx_context::TxContext,
    ) {
        let minted = coin::mint(treasury_cap, amount, ctx);
        sui::transfer::public_transfer(minted, recipient);
    }

    /// Transfer DUCK coin object to recipient.
    public fun transfer_token(coin_obj: Coin<DUCK_TOKEN>, recipient: address) {
        sui::transfer::public_transfer(coin_obj, recipient);
    }

    /// Burn DUCK using the treasury capability.
    public fun burn(treasury_cap: &mut TreasuryCap<DUCK_TOKEN>, coin_obj: Coin<DUCK_TOKEN>) {
        coin::burn(treasury_cap, coin_obj);
    }

    #[test]
    fun test_mint_and_burn_updates_total_supply() {
        let mut ctx = sui::tx_context::dummy();
        let mut cap = coin::create_treasury_cap_for_testing<DUCK_TOKEN>(&mut ctx);
        let sender = sui::tx_context::sender(&ctx);

        mint(&mut cap, 200, sender, &mut ctx);
        assert!(coin::total_supply(&cap) == 200, 1);

        let c = coin::mint(&mut cap, 300, &mut ctx);
        burn(&mut cap, c);
        assert!(coin::total_supply(&cap) == 200, 2);

        sui::transfer::public_transfer(cap, sender);
    }
}
