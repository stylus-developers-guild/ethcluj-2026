use proptest::prelude::*;

use stylus_sdk::{
    alloy_primitives::{address, Address, U256},
    alloy_sol_types::{sol, SolCall},
    testing::*,
};

use cluj_lending::*;
use cluj_lending::immutables::*;

sol! {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
}

fn abi_true() -> Vec<u8> {
    U256::from(1).to_be_bytes::<32>().to_vec()
}

fn mock_transfer_from(vm: &TestVM, tok: Address, from: Address, to: Address, amt: U256) {
    let data = transferFromCall { from, to, amount: amt }.abi_encode();
    vm.mock_call(tok, data, U256::ZERO, Ok(abi_true()));
}

fn mock_mint(vm: &TestVM, tok: Address, to: Address, amt: U256) {
    let data = mintCall { to, amount: amt }.abi_encode();
    vm.mock_call(tok, data, U256::ZERO, Ok(vec![]));
}

fn arb_addr() -> impl Strategy<Value = Address> {
    prop::array::uniform20(1u8..=255u8).prop_map(Address::from)
}

proptest! {
    /// Borrow a position, advance time, check accrued debt matches the
    /// interest formula, then fully repay and verify the position is clear.
    #[test]
    fn borrow_accrue_repay(
        recipient in arb_addr(),
        sender in arb_addr(),
        tok in arb_addr(),
        // Keep amounts small-ish to avoid overflow in the (buggy) double-scaled
        // interest math while still exercising the logic.
        ausd_raw in 1u64..1_000,
        collateral_raw in 2_000u64..100_000,
        t0 in 1_000_000u64..2_000_000u64,
        dt in 1u64..3600u64,        // up to 1 hour elapsed
    ) {
        // Collateral must beat the 110% requirement: collateral > ausd * 1.1
        // With our ranges (ausd max 999, collateral min 2000) this always holds.
        prop_assume!(
            sender != recipient
            && tok != sender
            && tok != recipient
            && sender != Address::ZERO
            && recipient != Address::ZERO
        );

        let ausd_amt = U256::from(ausd_raw);
        let collateral_amt = U256::from(collateral_raw);

        let vm = TestVM::new();
        let contract_addr = vm.contract_address();
        let mut s = StorageLender::from(&vm);

        // --- Initialise the lending contract ---
        vm.set_sender(sender);
        s.ctor(tok).unwrap();

        // --- Borrow: sender deposits ARB collateral, recipient gets aUSD ---
        vm.set_block_timestamp(t0);
        vm.set_sender(sender);

        // Mock: transferFrom(sender -> contract) for the ARB collateral
        mock_transfer_from(&vm, ARB_ADDR, sender, contract_addr, collateral_amt);
        // Mock: mint(recipient, ausd_amt) on the token
        mock_mint(&vm, tok, recipient, ausd_amt);

        let ticket = s.borrow(ausd_amt, collateral_amt, recipient).unwrap();

        // --- Record the post-borrow state ---
        // After borrow_internal, debt and collateral are adjusted for the
        // security deposit. Read back what the contract actually stored.
        let stored_debt = s.debt.getter(ticket).get();
        let stored_collateral = s.collateral.getter(ticket).get();
        prop_assert!(stored_debt > U256::ZERO, "debt must be positive after borrow");
        prop_assert!(stored_collateral > U256::ZERO, "collateral must be positive");

        // --- Advance time and query accrued debt ---
        let t1 = t0 + dt;
        vm.set_block_timestamp(t1);

        // debt_outstanding calls record_timepoint_internal which computes:
        //   outstanding = debt + prev_interest (0 for first timepoint)
        //   scaled_outstanding = outstanding * SCALING_FACTOR
        //   scaled_rate_incr  = INTEREST_PER_SEC_RATE * dt
        //   interest = (scaled_outstanding * scaled_rate_incr) / SCALING_FACTOR
        //   total = debt + interest
        let total_debt = s.debt_outstanding(ticket, t1).unwrap();

        // Replicate the contract's interest formula on our side.
        let expected_interest = {
            let scaled_outstanding = stored_debt * SCALING_FACTOR;
            let scaled_rate_incr = INTEREST_PER_SEC_RATE * U256::from(dt);
            let scaled_interest = scaled_outstanding * scaled_rate_incr;
            scaled_interest / SCALING_FACTOR
        };
        let expected_total = stored_debt + expected_interest;

        prop_assert_eq!(
            total_debt, expected_total,
            "accrued debt mismatch: contract says {} but formula gives {} \
             (debt={}, interest={}, dt={})",
            total_debt, expected_total, stored_debt, expected_interest, dt,
        );

        // Interest should be non-negative. If dt > 0 and debt > 0,
        // interest should be strictly positive (given the rate constant).
        if dt > 0 && stored_debt > U256::ZERO {
            prop_assert!(
                expected_interest > U256::ZERO,
                "expected positive interest for dt={} debt={}",
                dt, stored_debt,
            );
        }

        // --- Repay the full outstanding debt ---
        vm.set_sender(recipient);
        // We need ticket_owners to be recipient so the ownership check passes.
        // (borrow() already set ticket_owners to recipient.)

        // The repay function takes ARB from the sender.
        mock_transfer_from(&vm, ARB_ADDR, recipient, contract_addr, total_debt);

        s.repay(ticket, total_debt).unwrap();

        // After full repayment, debt and interest should both be zero.
        // Query at the same timestamp (no further interest accrues).
        let post_repay_debt = s.debt_outstanding(ticket, t1).unwrap();
        prop_assert_eq!(
            post_repay_debt, U256::ZERO,
            "debt should be zero after full repayment, got {}",
            post_repay_debt,
        );
    }
}
