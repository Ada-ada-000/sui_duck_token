module duck_lending::duck_lending {
    use duck_token::duck_token::DUCK_TOKEN as DUCK;
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::event;
    use sui::table::{Self, Table};

    const BPS_DENOMINATOR: u64 = 10_000;
    const DEFAULT_BORROW_LTV_BPS: u64 = 5_000;
    const DEFAULT_LIQUIDATION_LTV_BPS: u64 = 7_000;
    const DEFAULT_LIQUIDATION_BONUS_BPS: u64 = 500;
    const DEFAULT_BORROW_RATE_BPS_PER_EPOCH: u64 = 10;

    const E_NO_LOAN: u64 = 1001;
    const E_INSUFFICIENT_COLLATERAL: u64 = 1002;
    const E_LTV_RATIO_ERROR: u64 = 1003;
    const E_OUTSTANDING_DEBT: u64 = 1004;
    const E_PROTOCOL_PAUSED: u64 = 1005;
    const E_NOT_ADMIN: u64 = 1006;
    const E_BAD_RISK_PARAMS: u64 = 1007;
    const E_POSITION_HEALTHY: u64 = 1008;
    const E_INVALID_AMOUNT: u64 = 1009;

    public struct LoanPosition has store, drop {
        collateral: u64,
        debt: u64,
        last_interest_epoch: u64,
    }

    public struct RiskAdminCap has key, store {
        id: sui::object::UID,
        owner: address,
    }

    public struct DuckLending has key {
        id: sui::object::UID,
        collateral_pool: Balance<DUCK>,
        positions: Table<address, LoanPosition>,
        borrow_ltv_bps: u64,
        liquidation_ltv_bps: u64,
        liquidation_bonus_bps: u64,
        borrow_rate_bps_per_epoch: u64,
        paused: bool,
    }

    public struct PledgeEvent has copy, drop {
        user: address,
        amount: u64,
    }

    public struct BorrowEvent has copy, drop {
        user: address,
        amount: u64,
        total_debt: u64,
    }

    public struct RepayEvent has copy, drop {
        user: address,
        repaid: u64,
        remaining_debt: u64,
    }

    public struct RedeemEvent has copy, drop {
        user: address,
        amount: u64,
        remaining_collateral: u64,
    }

    public struct LiquidateEvent has copy, drop {
        liquidator: address,
        borrower: address,
        repaid: u64,
        seized: u64,
        remaining_debt: u64,
        remaining_collateral: u64,
    }

    public struct RiskParamsUpdatedEvent has copy, drop {
        borrow_ltv_bps: u64,
        liquidation_ltv_bps: u64,
        liquidation_bonus_bps: u64,
    }

    public struct PauseUpdatedEvent has copy, drop {
        paused: bool,
    }

    public struct InterestRateUpdatedEvent has copy, drop {
        borrow_rate_bps_per_epoch: u64,
    }

    public struct InterestAccruedEvent has copy, drop {
        user: address,
        old_debt: u64,
        new_debt: u64,
        from_epoch: u64,
        to_epoch: u64,
    }

    /// Internal pure helper for max debt under configurable LTV.
    fun max_debt_for(collateral: u64, ltv_bps: u64): u64 {
        (collateral * ltv_bps) / BPS_DENOMINATOR
    }

    /// Internal pure helper to compute debt after repayment.
    fun debt_after_repay(current_debt: u64, payment_value: u64): u64 {
        if (payment_value >= current_debt) 0 else current_debt - payment_value
    }

    fun debt_with_interest(debt: u64, delta_epoch: u64, rate_bps_per_epoch: u64): u64 {
        debt + ((debt * rate_bps_per_epoch * delta_epoch) / BPS_DENOMINATOR)
    }

    fun min_u64(a: u64, b: u64): u64 {
        if (a <= b) a else b
    }

    fun is_unhealthy(collateral: u64, debt: u64, liquidation_ltv_bps: u64): bool {
        debt * BPS_DENOMINATOR > collateral * liquidation_ltv_bps
    }

    fun seize_amount_for_liquidation(repay_amount: u64, bonus_bps: u64): u64 {
        (repay_amount * (BPS_DENOMINATOR + bonus_bps)) / BPS_DENOMINATOR
    }

    fun assert_admin(cap: &RiskAdminCap, sender: address) {
        assert!(cap.owner == sender, E_NOT_ADMIN);
    }

    fun assert_risk_params(borrow_ltv_bps: u64, liquidation_ltv_bps: u64, liquidation_bonus_bps: u64) {
        assert!(borrow_ltv_bps > 0, E_BAD_RISK_PARAMS);
        assert!(borrow_ltv_bps <= liquidation_ltv_bps, E_BAD_RISK_PARAMS);
        assert!(liquidation_ltv_bps < BPS_DENOMINATOR, E_BAD_RISK_PARAMS);
        assert!(liquidation_bonus_bps <= BPS_DENOMINATOR, E_BAD_RISK_PARAMS);
    }

    fun accrue_position_if_needed(
        user: address,
        position: &mut LoanPosition,
        current_epoch: u64,
        rate_bps_per_epoch: u64,
    ) {
        if (position.debt == 0) {
            position.last_interest_epoch = current_epoch;
            return
        };
        if (current_epoch <= position.last_interest_epoch) {
            return
        };
        let old_debt = position.debt;
        let new_debt = debt_with_interest(
            position.debt,
            current_epoch - position.last_interest_epoch,
            rate_bps_per_epoch,
        );
        position.debt = new_debt;
        event::emit(InterestAccruedEvent {
            user,
            old_debt,
            new_debt,
            from_epoch: position.last_interest_epoch,
            to_epoch: current_epoch,
        });
        position.last_interest_epoch = current_epoch;
    }

    /// Create lending pool as shared object.
    #[allow(lint(self_transfer))]
    public fun create_pool(ctx: &mut sui::tx_context::TxContext) {
        let sender = sui::tx_context::sender(ctx);
        let pool = DuckLending {
            id: sui::object::new(ctx),
            collateral_pool: balance::zero(),
            positions: table::new(ctx),
            borrow_ltv_bps: DEFAULT_BORROW_LTV_BPS,
            liquidation_ltv_bps: DEFAULT_LIQUIDATION_LTV_BPS,
            liquidation_bonus_bps: DEFAULT_LIQUIDATION_BONUS_BPS,
            borrow_rate_bps_per_epoch: DEFAULT_BORROW_RATE_BPS_PER_EPOCH,
            paused: false,
        };
        let admin_cap = RiskAdminCap {
            id: sui::object::new(ctx),
            owner: sender,
        };
        sui::transfer::public_transfer(admin_cap, sender);
        sui::transfer::share_object(pool);
    }

    /// Update protocol risk parameters.
    public fun set_risk_params(
        pool: &mut DuckLending,
        cap: &RiskAdminCap,
        borrow_ltv_bps: u64,
        liquidation_ltv_bps: u64,
        liquidation_bonus_bps: u64,
        ctx: &sui::tx_context::TxContext,
    ) {
        let sender = sui::tx_context::sender(ctx);
        assert_admin(cap, sender);
        assert_risk_params(borrow_ltv_bps, liquidation_ltv_bps, liquidation_bonus_bps);

        pool.borrow_ltv_bps = borrow_ltv_bps;
        pool.liquidation_ltv_bps = liquidation_ltv_bps;
        pool.liquidation_bonus_bps = liquidation_bonus_bps;
        event::emit(RiskParamsUpdatedEvent {
            borrow_ltv_bps,
            liquidation_ltv_bps,
            liquidation_bonus_bps,
        });
    }

    /// Update per-epoch debt interest rate in basis points.
    public fun set_interest_rate(
        pool: &mut DuckLending,
        cap: &RiskAdminCap,
        borrow_rate_bps_per_epoch: u64,
        ctx: &sui::tx_context::TxContext,
    ) {
        let sender = sui::tx_context::sender(ctx);
        assert_admin(cap, sender);
        assert!(borrow_rate_bps_per_epoch <= BPS_DENOMINATOR, E_BAD_RISK_PARAMS);
        pool.borrow_rate_bps_per_epoch = borrow_rate_bps_per_epoch;
        event::emit(InterestRateUpdatedEvent { borrow_rate_bps_per_epoch });
    }

    /// Pause or unpause borrowing/redeeming/liquidation.
    public fun set_paused(
        pool: &mut DuckLending,
        cap: &RiskAdminCap,
        paused: bool,
        ctx: &sui::tx_context::TxContext,
    ) {
        let sender = sui::tx_context::sender(ctx);
        assert_admin(cap, sender);
        pool.paused = paused;
        event::emit(PauseUpdatedEvent { paused });
    }

    /// Pledge DUCK as collateral.
    public fun pledge(pool: &mut DuckLending, collateral_coin: Coin<DUCK>, ctx: &sui::tx_context::TxContext) {
        let sender = sui::tx_context::sender(ctx);
        let amount = coin::value(&collateral_coin);
        assert!(amount > 0, E_INSUFFICIENT_COLLATERAL);

        coin::put(&mut pool.collateral_pool, collateral_coin);

        if (table::contains(&pool.positions, sender)) {
            let position = table::borrow_mut(&mut pool.positions, sender);
            accrue_position_if_needed(
                sender,
                position,
                sui::tx_context::epoch(ctx),
                pool.borrow_rate_bps_per_epoch,
            );
            position.collateral = position.collateral + amount;
        } else {
            table::add(
                &mut pool.positions,
                sender,
                LoanPosition {
                    collateral: amount,
                    debt: 0,
                    last_interest_epoch: sui::tx_context::epoch(ctx),
                },
            );
        };
        event::emit(PledgeEvent { user: sender, amount });
    }

    /// Borrow DUCK from collateral pool with max LTV 50%.
    #[allow(lint(self_transfer))]
    public fun borrow(pool: &mut DuckLending, amount: u64, ctx: &mut sui::tx_context::TxContext) {
        assert!(!pool.paused, E_PROTOCOL_PAUSED);
        assert!(amount > 0, E_INVALID_AMOUNT);
        let sender = sui::tx_context::sender(ctx);
        assert!(table::contains(&pool.positions, sender), E_INSUFFICIENT_COLLATERAL);

        let position = table::borrow_mut(&mut pool.positions, sender);
        accrue_position_if_needed(
            sender,
            position,
            sui::tx_context::epoch(ctx),
            pool.borrow_rate_bps_per_epoch,
        );
        assert!(position.collateral > 0, E_INSUFFICIENT_COLLATERAL);

        let max_debt = max_debt_for(position.collateral, pool.borrow_ltv_bps);
        let new_debt = position.debt + amount;
        assert!(new_debt <= max_debt, E_LTV_RATIO_ERROR);
        assert!(balance::value(&pool.collateral_pool) >= amount, E_INSUFFICIENT_COLLATERAL);

        position.debt = new_debt;
        let borrowed = coin::take(&mut pool.collateral_pool, amount, ctx);
        sui::transfer::public_transfer(borrowed, sender);
        event::emit(BorrowEvent {
            user: sender,
            amount,
            total_debt: position.debt,
        });
    }

    /// Repay DUCK debt.
    #[allow(lint(self_transfer))]
    public fun repay(pool: &mut DuckLending, mut payment: Coin<DUCK>, ctx: &mut sui::tx_context::TxContext) {
        let sender = sui::tx_context::sender(ctx);
        assert!(table::contains(&pool.positions, sender), E_NO_LOAN);

        let position = table::borrow_mut(&mut pool.positions, sender);
        accrue_position_if_needed(
            sender,
            position,
            sui::tx_context::epoch(ctx),
            pool.borrow_rate_bps_per_epoch,
        );
        assert!(position.debt > 0, E_NO_LOAN);

        let debt = position.debt;
        let payment_value = coin::value(&payment);
        let actual_repay = min_u64(payment_value, debt);

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
        event::emit(RepayEvent {
            user: sender,
            repaid: actual_repay,
            remaining_debt: position.debt,
        });
    }

    /// Redeem collateral after loan is fully repaid.
    #[allow(lint(self_transfer))]
    public fun redeem(pool: &mut DuckLending, amount: u64, ctx: &mut sui::tx_context::TxContext) {
        assert!(!pool.paused, E_PROTOCOL_PAUSED);
        let sender = sui::tx_context::sender(ctx);
        assert!(table::contains(&pool.positions, sender), E_NO_LOAN);

        let should_remove_position = {
            let position = table::borrow_mut(&mut pool.positions, sender);
            accrue_position_if_needed(
                sender,
                position,
                sui::tx_context::epoch(ctx),
                pool.borrow_rate_bps_per_epoch,
            );
            assert!(position.debt == 0, E_OUTSTANDING_DEBT);
            assert!(amount > 0 && amount <= position.collateral, E_INSUFFICIENT_COLLATERAL);
            assert!(balance::value(&pool.collateral_pool) >= amount, E_INSUFFICIENT_COLLATERAL);

            position.collateral = position.collateral - amount;
            event::emit(RedeemEvent {
                user: sender,
                amount,
                remaining_collateral: position.collateral,
            });
            position.collateral == 0
        };

        let collateral_coin = coin::take(&mut pool.collateral_pool, amount, ctx);
        sui::transfer::public_transfer(collateral_coin, sender);

        if (should_remove_position) {
            let _ = table::remove(&mut pool.positions, sender);
        };
    }

    /// Liquidate unhealthy position by repaying debt and seizing collateral with bonus.
    #[allow(lint(self_transfer))]
    public fun liquidate(
        pool: &mut DuckLending,
        borrower: address,
        mut payment: Coin<DUCK>,
        ctx: &mut sui::tx_context::TxContext,
    ) {
        assert!(!pool.paused, E_PROTOCOL_PAUSED);
        assert!(table::contains(&pool.positions, borrower), E_NO_LOAN);
        let payment_value = coin::value(&payment);
        assert!(payment_value > 0, E_INVALID_AMOUNT);

        let (repay_amount, seize_amount, should_remove_position) = {
            let position = table::borrow_mut(&mut pool.positions, borrower);
            accrue_position_if_needed(
                borrower,
                position,
                sui::tx_context::epoch(ctx),
                pool.borrow_rate_bps_per_epoch,
            );
            assert!(position.debt > 0, E_NO_LOAN);
            assert!(
                is_unhealthy(position.collateral, position.debt, pool.liquidation_ltv_bps),
                E_POSITION_HEALTHY
            );

            let repay_amount = min_u64(payment_value, position.debt);
            position.debt = debt_after_repay(position.debt, repay_amount);

            let mut seize = seize_amount_for_liquidation(repay_amount, pool.liquidation_bonus_bps);
            if (seize > position.collateral) {
                seize = position.collateral;
            };
            position.collateral = position.collateral - seize;

            let remaining_debt = position.debt;
            let remaining_collateral = position.collateral;
            event::emit(LiquidateEvent {
                liquidator: sui::tx_context::sender(ctx),
                borrower,
                repaid: repay_amount,
                seized: seize,
                remaining_debt,
                remaining_collateral,
            });
            (repay_amount, seize, position.collateral == 0 && position.debt == 0)
        };

        if (payment_value > repay_amount) {
            let repay_coin = coin::split(&mut payment, repay_amount, ctx);
            coin::put(&mut pool.collateral_pool, repay_coin);
            sui::transfer::public_transfer(payment, sui::tx_context::sender(ctx));
        } else {
            coin::put(&mut pool.collateral_pool, payment);
        };

        assert!(balance::value(&pool.collateral_pool) >= seize_amount, E_INSUFFICIENT_COLLATERAL);
        let seized = coin::take(&mut pool.collateral_pool, seize_amount, ctx);
        sui::transfer::public_transfer(seized, sui::tx_context::sender(ctx));

        if (should_remove_position) {
            let _ = table::remove(&mut pool.positions, borrower);
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

    /// Explicit interest accrual hook for offchain keepers.
    public fun accrue_interest(pool: &mut DuckLending, user: address, ctx: &sui::tx_context::TxContext) {
        if (!table::contains(&pool.positions, user)) return;
        let position = table::borrow_mut(&mut pool.positions, user);
        accrue_position_if_needed(
            user,
            position,
            sui::tx_context::epoch(ctx),
            pool.borrow_rate_bps_per_epoch,
        );
    }

    #[test_only]
    fun new_pool_for_testing(ctx: &mut sui::tx_context::TxContext): DuckLending {
        DuckLending {
            id: sui::object::new(ctx),
            collateral_pool: balance::zero(),
            positions: table::new(ctx),
            borrow_ltv_bps: DEFAULT_BORROW_LTV_BPS,
            liquidation_ltv_bps: DEFAULT_LIQUIDATION_LTV_BPS,
            liquidation_bonus_bps: DEFAULT_LIQUIDATION_BONUS_BPS,
            borrow_rate_bps_per_epoch: DEFAULT_BORROW_RATE_BPS_PER_EPOCH,
            paused: false,
        }
    }

    #[test_only]
    fun new_admin_cap_for_testing(owner: address, ctx: &mut sui::tx_context::TxContext): RiskAdminCap {
        RiskAdminCap {
            id: sui::object::new(ctx),
            owner,
        }
    }

    #[test_only]
    fun destroy_admin_cap_for_testing(cap: RiskAdminCap) {
        let RiskAdminCap { id, owner: _ } = cap;
        sui::object::delete(id);
    }

    #[test_only]
    fun destroy_pool_for_testing(pool: DuckLending) {
        let DuckLending {
            id,
            collateral_pool,
            positions,
            borrow_ltv_bps: _,
            liquidation_ltv_bps: _,
            liquidation_bonus_bps: _,
            borrow_rate_bps_per_epoch: _,
            paused: _,
        } = pool;
        let _ = balance::destroy_for_testing(collateral_pool);
        table::drop(positions);
        sui::object::delete(id);
    }

    #[test]
    fun test_max_debt_for() {
        assert!(max_debt_for(0, 5_000) == 0, 1);
        assert!(max_debt_for(2, 5_000) == 1, 2);
        assert!(max_debt_for(1_000_000_000, 5_000) == 500_000_000, 3);
        assert!(max_debt_for(3, 5_000) == 1, 4);
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
        assert!(max_debt_for(5, 5_000) == 2, 31);
        assert!(max_debt_for(7, 5_000) == 3, 32);
    }

    #[test]
    fun test_liquidation_math_helpers() {
        assert!(is_unhealthy(100, 71, 7_000), 33);
        assert!(!is_unhealthy(100, 70, 7_000), 34);
        assert!(seize_amount_for_liquidation(100, 500) == 105, 35);
    }

    #[test]
    fun test_debt_after_repay_zero_debt() {
        assert!(debt_after_repay(0, 0) == 0, 41);
        assert!(debt_after_repay(0, 999) == 0, 42);
    }

    #[test]
    fun test_interest_math() {
        assert!(debt_with_interest(100, 10, 10) == 101, 43);
        assert!(debt_with_interest(1_000, 100, 100) == 2_000, 44);
    }

    #[test]
    fun test_flow_pledge_borrow_repay_redeem() {
        let mut ctx = sui::tx_context::dummy();
        let mut pool = new_pool_for_testing(&mut ctx);

        let collateral = coin::mint_for_testing<DUCK>(1_000, &mut ctx);
        pledge(&mut pool, collateral, &ctx);
        let (c1, d1) = get_loan_info(&pool, sui::tx_context::sender(&ctx));
        assert!(c1 == 1_000, 51);
        assert!(d1 == 0, 52);

        borrow(&mut pool, 500, &mut ctx);
        let (c2, d2) = get_loan_info(&pool, sui::tx_context::sender(&ctx));
        assert!(c2 == 1_000, 53);
        assert!(d2 == 500, 54);

        let payment = coin::mint_for_testing<DUCK>(500, &mut ctx);
        repay(&mut pool, payment, &mut ctx);
        let (c3, d3) = get_loan_info(&pool, sui::tx_context::sender(&ctx));
        assert!(c3 == 1_000, 55);
        assert!(d3 == 0, 56);

        redeem(&mut pool, 1_000, &mut ctx);
        let (c4, d4) = get_loan_info(&pool, sui::tx_context::sender(&ctx));
        assert!(c4 == 0, 57);
        assert!(d4 == 0, 58);
        destroy_pool_for_testing(pool);
    }

    #[test, expected_failure(abort_code = E_LTV_RATIO_ERROR)]
    fun test_borrow_above_ltv_fails() {
        let mut ctx = sui::tx_context::dummy();
        let mut pool = new_pool_for_testing(&mut ctx);
        let collateral = coin::mint_for_testing<DUCK>(100, &mut ctx);
        pledge(&mut pool, collateral, &ctx);
        borrow(&mut pool, 51, &mut ctx);
        abort 991
    }

    #[test, expected_failure(abort_code = E_OUTSTANDING_DEBT)]
    fun test_redeem_with_debt_fails() {
        let mut ctx = sui::tx_context::dummy();
        let mut pool = new_pool_for_testing(&mut ctx);
        let collateral = coin::mint_for_testing<DUCK>(100, &mut ctx);
        pledge(&mut pool, collateral, &ctx);
        borrow(&mut pool, 50, &mut ctx);
        redeem(&mut pool, 10, &mut ctx);
        abort 992
    }

    #[test]
    fun test_liquidation_flow() {
        let mut ctx = sui::tx_context::dummy();
        let sender = sui::tx_context::sender(&ctx);
        let mut pool = new_pool_for_testing(&mut ctx);
        let admin = new_admin_cap_for_testing(sender, &mut ctx);

        let collateral = coin::mint_for_testing<DUCK>(100, &mut ctx);
        pledge(&mut pool, collateral, &ctx);
        borrow(&mut pool, 50, &mut ctx);

        set_risk_params(&mut pool, &admin, 4_000, 4_000, 500, &ctx);
        let liquidator_payment = coin::mint_for_testing<DUCK>(20, &mut ctx);
        liquidate(&mut pool, sender, liquidator_payment, &mut ctx);
        let (collateral_left, debt_left) = get_loan_info(&pool, sender);
        assert!(collateral_left == 79, 61);
        assert!(debt_left == 30, 62);

        let final_repay = coin::mint_for_testing<DUCK>(30, &mut ctx);
        repay(&mut pool, final_repay, &mut ctx);
        redeem(&mut pool, 79, &mut ctx);

        destroy_admin_cap_for_testing(admin);
        destroy_pool_for_testing(pool);
    }

    #[test, expected_failure(abort_code = E_POSITION_HEALTHY)]
    fun test_liquidate_healthy_position_fails() {
        let mut ctx = sui::tx_context::dummy();
        let sender = sui::tx_context::sender(&ctx);
        let mut pool = new_pool_for_testing(&mut ctx);

        let collateral = coin::mint_for_testing<DUCK>(100, &mut ctx);
        pledge(&mut pool, collateral, &ctx);
        borrow(&mut pool, 50, &mut ctx);

        let payment = coin::mint_for_testing<DUCK>(10, &mut ctx);
        liquidate(&mut pool, sender, payment, &mut ctx);
        abort 993
    }

    #[test, expected_failure(abort_code = E_NOT_ADMIN)]
    fun test_non_admin_cannot_set_risk_params() {
        let mut owner_ctx = sui::tx_context::dummy();
        let owner = sui::tx_context::sender(&owner_ctx);
        let mut pool = new_pool_for_testing(&mut owner_ctx);
        let admin = new_admin_cap_for_testing(owner, &mut owner_ctx);

        let attacker_ctx = sui::tx_context::new_from_hint(@0x1, 2, 0, 0, 0);
        set_risk_params(&mut pool, &admin, 5_000, 6_000, 500, &attacker_ctx);
        abort 994
    }

    #[test]
    fun test_interest_accrues_with_epoch_progress() {
        let mut borrower_ctx = sui::tx_context::dummy();
        let borrower = sui::tx_context::sender(&borrower_ctx);
        let mut pool = new_pool_for_testing(&mut borrower_ctx);
        let admin = new_admin_cap_for_testing(borrower, &mut borrower_ctx);

        set_interest_rate(&mut pool, &admin, 100, &borrower_ctx);
        let collateral = coin::mint_for_testing<DUCK>(200, &mut borrower_ctx);
        pledge(&mut pool, collateral, &borrower_ctx);
        borrow(&mut pool, 100, &mut borrower_ctx);

        let epoch_plus_ten_ctx = sui::tx_context::new_from_hint(@0x3, 3, 10, 0, 0);
        accrue_interest(&mut pool, borrower, &epoch_plus_ten_ctx);
        let (_, debt_after) = get_loan_info(&pool, borrower);
        assert!(debt_after == 110, 95);

        let mut borrower_ctx_settle = sui::tx_context::new_from_hint(borrower, 5, 10, 0, 0);
        let pay = coin::mint_for_testing<DUCK>(110, &mut borrower_ctx_settle);
        repay(&mut pool, pay, &mut borrower_ctx_settle);
        redeem(&mut pool, 200, &mut borrower_ctx_settle);
        destroy_admin_cap_for_testing(admin);
        destroy_pool_for_testing(pool);
    }

    #[test]
    fun test_multi_address_liquidation() {
        let mut borrower_ctx = sui::tx_context::dummy();
        let borrower = sui::tx_context::sender(&borrower_ctx);
        let mut pool = new_pool_for_testing(&mut borrower_ctx);
        let admin = new_admin_cap_for_testing(borrower, &mut borrower_ctx);

        let collateral = coin::mint_for_testing<DUCK>(100, &mut borrower_ctx);
        pledge(&mut pool, collateral, &borrower_ctx);
        borrow(&mut pool, 50, &mut borrower_ctx);
        set_risk_params(&mut pool, &admin, 4_000, 4_000, 500, &borrower_ctx);

        let mut liquidator_ctx = sui::tx_context::new_from_hint(@0x2, 4, 1, 0, 0);
        let repay_coin = coin::mint_for_testing<DUCK>(20, &mut liquidator_ctx);
        liquidate(&mut pool, borrower, repay_coin, &mut liquidator_ctx);

        let (c_left, d_left) = get_loan_info(&pool, borrower);
        assert!(c_left == 79, 96);
        assert!(d_left == 30, 97);

        let mut borrower_ctx_settle = sui::tx_context::new_from_hint(borrower, 6, 1, 0, 0);
        let final_repay = coin::mint_for_testing<DUCK>(30, &mut borrower_ctx_settle);
        repay(&mut pool, final_repay, &mut borrower_ctx_settle);
        redeem(&mut pool, 79, &mut borrower_ctx_settle);
        destroy_admin_cap_for_testing(admin);
        destroy_pool_for_testing(pool);
    }
}
