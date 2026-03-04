module duck_vault::duck_vault {
    use duck_token::duck_token::DUCK_TOKEN as DUCK;
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};

    const E_NOT_OWNER: u64 = 1;

    public struct DuckVault has key, store {
        id: sui::object::UID,
        owner: address,
        vault_balance: Balance<DUCK>,
    }

    /// Create an empty personal vault.
    public fun create_vault(ctx: &mut sui::tx_context::TxContext) {
        let vault = DuckVault {
            id: sui::object::new(ctx),
            owner: sui::tx_context::sender(ctx),
            vault_balance: balance::zero(),
        };
        sui::transfer::public_transfer(vault, sui::tx_context::sender(ctx));
    }

    /// Deposit DUCK into vault.
    public fun deposit(vault: &mut DuckVault, coin_obj: Coin<DUCK>, ctx: &sui::tx_context::TxContext) {
        assert!(vault.owner == sui::tx_context::sender(ctx), E_NOT_OWNER);
        coin::put(&mut vault.vault_balance, coin_obj);
    }

    /// Withdraw DUCK from vault to owner.
    public fun withdraw(vault: &mut DuckVault, amount: u64, ctx: &mut sui::tx_context::TxContext) {
        assert!(vault.owner == sui::tx_context::sender(ctx), E_NOT_OWNER);
        let coin_obj = coin::take(&mut vault.vault_balance, amount, ctx);
        sui::transfer::public_transfer(coin_obj, sui::tx_context::sender(ctx));
    }

    /// Query vault DUCK balance.
    public fun balance_of(vault: &DuckVault): u64 {
        balance::value(&vault.vault_balance)
    }
}
