module duck_lending::duck_lending {
    use duck_token::duck_token::DUCK_TOKEN as DUCK;
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::table::{Self, Table};

    const LTV_NUMERATOR: u64 = 50;
    const LTV_DENOMINATOR: u64 = 100;

    const E_NO_LOAN: u64 = 1001;
    const E_INSUFFICIENT_COLLATERAL: u64 = 1002;
    const E_LTV_RATIO_ERROR: u64 = 1003;
    const E_OUTSTANDING_DEBT: u64 = 1004;

    public struct LoanPosition has store, drop {
        collateral: u64,
        debt: u64,
    }

    public struct DuckLending has key {
        id: sui::object::UID,
        collateral_pool: Balance<DUCK>,
        positions: Table<address, LoanPosition>,
    }

    /// Internal pure helper for max debt under fixed LTV.
    fun max_debt_for(collateral: u64): u64 {
        (collateral * LTV_NUMERATOR) / LTV_DENOMINATOR
    }

    /// Internal pure helper to compute debt after repayment.
    fun debt_after_repay(current_debt: u64, payment_value: u64): u64 {
        if (payment_value >= current_debt) 0 else current_debt - payment_value
    }

    /// Create lending pool as shared object.
    public fun create_pool(ctx: &mut sui::tx_context::TxContext) {
        let pool = DuckLending {
            id: sui::object::new(ctx),
            collateral_pool: balance::zero(),
            positions: table::new(ctx),
        };
        sui::transfer::share_object(pool);
    }

    /// Pledge DUCK as collateral.
    public fun pledge(pool: &mut DuckLending, collateral_coin: Coin<DUCK>, ctx: &sui::tx_context::TxContext) {
        let sender = sui::tx_context::sender(ctx);
        let amount = coin::value(&collateral_coin);
        assert!(amount > 0, E_INSUFFICIENT_COLLATERAL);

        coin::put(&mut pool.collateral_pool, collateral_coin);

        if (table::contains(&pool.positions, sender)) {
            let position = table::borrow_mut(&mut pool.positions, sender);
            position.collateral = position.collateral + amount;
        } else {
            table::add(
                &mut pool.positions,
                sender,
                LoanPosition {
                    collateral: amount,
                    debt: 0,
                },
            );
        };
    }

    /// Borrow DUCK from collateral pool with max LTV 50%.
    public fun borrow(pool: &mut DuckLending, amount: u64, ctx: &mut sui::tx_context::TxContext) {
        let sender = sui::tx_context::sender(ctx);
        assert!(table::contains(&pool.positions, sender), E_INSUFFICIENT_COLLATERAL);

        let position = table::borrow_mut(&mut pool.positions, sender);
        assert!(position.collateral > 0, E_INSUFFICIENT_COLLATERAL);

        let max_debt = max_debt_for(position.collateral);
        let new_debt = position.debt + amount;
        assert!(new_debt <= max_debt, E_LTV_RATIO_ERROR);
        assert!(balance::value(&pool.collateral_pool) >= amount, E_INSUFFICIENT_COLLATERAL);

        position.debt = new_debt;
        let borrowed = coin::take(&mut pool.collateral_pool, amount, ctx);
        sui::transfer::public_transfer(borrowed, sender);
    }

    /// Repay DUCK debt.
    public fun repay(pool: &mut DuckLending, mut payment: Coin<DUCK>, ctx: &mut sui::tx_context::TxContext) {
        let sender = sui::tx_context::sender(ctx);
        assert!(table::contains(&pool.positions, sender), E_NO_LOAN);

        let position = table::borrow_mut(&mut pool.positions, sender);
        assert!(position.debt > 0, E_NO_LOAN);

        let debt = position.debt;
        let payment_value = coin::value(&payment);

        if (payment_value >= debt) {
            let repay_coin = coin::split(&mut payment, debt, ctx);
            coin::put(&mut pool.collateral_pool, repay_coin);
            position.debt = debt_after_repay(debt, debt);

            if (coin::value(&payment) > 0) {
                sui::transfer::public_transfer(payment, sender);
            } else {
                coin::destroy_zero(payment);
            };
        } else {
            coin::put(&mut pool.collateral_pool, payment);
            position.debt = debt_after_repay(debt, payment_value);
        };
    }

    /// Redeem collateral after loan is fully repaid.
    public fun redeem(pool: &mut DuckLending, amount: u64, ctx: &mut sui::tx_context::TxContext) {
        let sender = sui::tx_context::sender(ctx);
        assert!(table::contains(&pool.positions, sender), E_NO_LOAN);

        let should_remove_position = {
            let position = table::borrow_mut(&mut pool.positions, sender);
            assert!(position.debt == 0, E_OUTSTANDING_DEBT);
            assert!(amount > 0 && amount <= position.collateral, E_INSUFFICIENT_COLLATERAL);
            assert!(balance::value(&pool.collateral_pool) >= amount, E_INSUFFICIENT_COLLATERAL);

            position.collateral = position.collateral - amount;
            position.collateral == 0
        };

        let collateral_coin = coin::take(&mut pool.collateral_pool, amount, ctx);
        sui::transfer::public_transfer(collateral_coin, sender);

        if (should_remove_position) {
            let _ = table::remove(&mut pool.positions, sender);
        };
    }

    /// Query any user's loan information: (collateral, debt).
    public fun get_loan_info(pool: &DuckLending, user: address): (u64, u64) {
        if (table::contains(&pool.positions, user)) {
            let position = table::borrow(&pool.positions, user);
            (position.collateral, position.debt)
        } else {
            (0, 0)
        }
    }

    #[test]
    fun test_max_debt_for() {
        assert!(max_debt_for(0) == 0, 1);
        assert!(max_debt_for(2) == 1, 2);
        assert!(max_debt_for(1_000_000_000) == 500_000_000, 3);
        assert!(max_debt_for(3) == 1, 4);
    }

    #[test]
    fun test_debt_after_repay_partial() {
        assert!(debt_after_repay(100, 20) == 80, 11);
        assert!(debt_after_repay(100, 99) == 1, 12);
        assert!(debt_after_repay(100, 0) == 100, 13);
    }

    #[test]
    fun test_debt_after_repay_full_or_overpay() {
        assert!(debt_after_repay(100, 100) == 0, 21);
        assert!(debt_after_repay(100, 120) == 0, 22);
        assert!(debt_after_repay(0, 10) == 0, 23);
    }

    #[test]
    fun test_max_debt_rounding_floor() {
        assert!(max_debt_for(5) == 2, 31);
        assert!(max_debt_for(7) == 3, 32);
    }

    #[test]
    fun test_debt_after_repay_zero_debt() {
        assert!(debt_after_repay(0, 0) == 0, 41);
        assert!(debt_after_repay(0, 999) == 0, 42);
    }
}
