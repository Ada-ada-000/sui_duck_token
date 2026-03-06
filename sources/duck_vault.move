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
    #[allow(lint(self_transfer))]
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
    #[allow(lint(self_transfer))]
    public fun withdraw(vault: &mut DuckVault, amount: u64, ctx: &mut sui::tx_context::TxContext) {
        assert!(vault.owner == sui::tx_context::sender(ctx), E_NOT_OWNER);
        let coin_obj = coin::take(&mut vault.vault_balance, amount, ctx);
        sui::transfer::public_transfer(coin_obj, sui::tx_context::sender(ctx));
    }

    /// Query vault DUCK balance.
    public fun balance_of(vault: &DuckVault): u64 {
        balance::value(&vault.vault_balance)
    }

    #[test_only]
    fun new_vault_for_testing(owner: address, ctx: &mut sui::tx_context::TxContext): DuckVault {
        DuckVault {
            id: sui::object::new(ctx),
            owner,
            vault_balance: balance::zero(),
        }
    }

    #[test]
    fun test_vault_deposit_withdraw_balance() {
        let mut ctx = sui::tx_context::dummy();
        let owner = sui::tx_context::sender(&ctx);
        let mut vault = new_vault_for_testing(owner, &mut ctx);

        let c1 = coin::mint_for_testing<DUCK>(100, &mut ctx);
        deposit(&mut vault, c1, &ctx);
        assert!(balance_of(&vault) == 100, 11);

        withdraw(&mut vault, 40, &mut ctx);
        assert!(balance_of(&vault) == 60, 12);

        withdraw(&mut vault, 60, &mut ctx);
        assert!(balance_of(&vault) == 0, 13);

        sui::transfer::public_transfer(vault, owner);
    }

    #[test, expected_failure(abort_code = E_NOT_OWNER)]
    fun test_vault_non_owner_cannot_deposit() {
        let mut owner_ctx = sui::tx_context::dummy();
        let owner = sui::tx_context::sender(&owner_ctx);
        let mut vault = new_vault_for_testing(owner, &mut owner_ctx);

        let mut attacker_ctx = sui::tx_context::new_from_hint(@0x1, 1, 0, 0, 0);
        let attacker_coin = coin::mint_for_testing<DUCK>(10, &mut attacker_ctx);
        deposit(&mut vault, attacker_coin, &attacker_ctx);
        abort 99
    }
}
