module duck_token::duck_token {
    use sui::coin::{Self, Coin, TreasuryCap};

    /// DUCK token type.
    public struct DUCK has drop, store {}

    /// One-time witness required by Sui `init` convention.
    public struct DUCK_TOKEN has drop {}

    /// Called automatically on package publish.
    fun init(_otw: DUCK_TOKEN, ctx: &mut sui::tx_context::TxContext) {
        let (treasury_cap, metadata) = coin::create_currency(
            DUCK {},
            9,
            b"DUCK",
            b"Decentral Universal Credit Kernel",
            b"Decentralized universal credit kernel, on-chain credit, cross-chain settlement.",
            option::none(),
            ctx,
        );

        sui::transfer::public_transfer(treasury_cap, sui::tx_context::sender(ctx));
        sui::transfer::public_freeze_object(metadata);
    }

    /// Mint DUCK to recipient.
    public fun mint(
        treasury_cap: &mut TreasuryCap<DUCK>,
        amount: u64,
        recipient: address,
        ctx: &mut sui::tx_context::TxContext,
    ) {
        let minted = coin::mint(treasury_cap, amount, ctx);
        sui::transfer::public_transfer(minted, recipient);
    }

    /// Transfer DUCK coin object to recipient.
    public fun transfer_token(coin_obj: Coin<DUCK>, recipient: address) {
        sui::transfer::public_transfer(coin_obj, recipient);
    }

    /// Burn DUCK using the treasury capability.
    public fun burn(treasury_cap: &mut TreasuryCap<DUCK>, coin_obj: Coin<DUCK>) {
        coin::burn(treasury_cap, coin_obj);
    }
}
