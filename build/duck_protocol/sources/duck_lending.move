module duck_lending::duck_lending {
    use duck_token::duck_token::DUCK;
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::table::{Self, Table};

    const LTV_NUMERATOR: u64 = 50;
    const LTV_DENOMINATOR: u64 = 100;

    const E_NO_LOAN: u64 = 1001;
    const E_INSUFFICIENT_COLLATERAL: u64 = 1002;
    const E_LTV_RATIO_ERROR: u64 = 1003;

    public struct LoanPosition has store, drop {
        collateral: u64,
        debt: u64,
    }

    public struct DuckLending has key {
        id: sui::object::UID,
        collateral_pool: Balance<DUCK>,
        positions: Table<address, LoanPosition>,
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

        let max_debt = (position.collateral * LTV_NUMERATOR) / LTV_DENOMINATOR;
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
            position.debt = 0;

            if (coin::value(&payment) > 0) {
                sui::transfer::public_transfer(payment, sender);
            } else {
                coin::destroy_zero(payment);
            };
        } else {
            coin::put(&mut pool.collateral_pool, payment);
            position.debt = debt - payment_value;
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
}
