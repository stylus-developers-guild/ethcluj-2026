use proptest::prelude::*;

use stylus_sdk::{
    alloy_primitives::{Address, U256},
    alloy_sol_types::{sol, SolCall},
    testing::*,
};

use cluj_lending::immutables::*;
use cluj_lending::Storage;

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
    vm.mock_call(tok, data, U256::ZERO, Ok(abi_true()));
}

/// Fixed addresses to avoid mock collisions with ARB_ADDR or contract_address.
fn sender_addr() -> Address { Address::from([0x01; 20]) }
fn recipient_addr() -> Address { Address::from([0x02; 20]) }
fn tok_addr() -> Address { Address::from([0x03; 20]) }

proptest! {
    /// Borrow a position, advance time, check accrued debt matches the
    /// interest formula, then fully repay and verify the position is clear.
    #[test]
    fn borrow_accrue_repay(
        ausd_raw in 1u64..1_000,
        collateral_raw in 2_000u64..100_000,
        t0 in 1_000_000u64..2_000_000u64,
        dt in 1u64..3600u64,
    ) {
        let sender = sender_addr();
        let recipient = recipient_addr();
        let tok = tok_addr();

        let vm = TestVM::new();
        let contract_addr = vm.contract_address();
        let mut s = Storage::from(&vm);

        let ausd_amt = U256::from(ausd_raw);
        let collateral_amt = U256::from(collateral_raw);

        // --- Initialise ---
        vm.set_sender(sender);
        s.ctor(tok).unwrap();

        // --- Borrow ---
        vm.set_block_timestamp(t0);
        vm.set_sender(sender);
        mock_transfer_from(&vm, ARB_ADDR, sender, contract_addr, collateral_amt);
        mock_mint(&vm, tok, recipient, ausd_amt);

        let ticket = s.borrow(ausd_amt, collateral_amt, recipient).unwrap();

        // Read back what the contract actually stored (adjusted for security deposit).
        let stored_debt = s.debt.getter(ticket).get();
        let stored_collateral = s.collateral.getter(ticket).get();
        prop_assert!(stored_debt > U256::ZERO, "debt must be positive after borrow");
        prop_assert!(stored_collateral > U256::ZERO, "collateral must be positive");

        // --- Advance time and query accrued debt ---
        let t1 = t0 + dt;
        vm.set_block_timestamp(t1);

        // debt_outstanding calls internal_record_timepoint which computes:
        //   scaled_outstanding = (debt + prev_interest) * SCALING_FACTOR
        //   scaled_rate_incr   = INTEREST_PER_SEC_RATE * dt
        //   interest = (scaled_outstanding * scaled_rate_incr) / SCALING_FACTOR
        //   total = debt + interest
        let total_debt = s.debt_outstanding(ticket, t1).unwrap();

        // Replicate the contract's interest formula.
        let expected_interest = {
            let scaled_outstanding = stored_debt * SCALING_FACTOR;
            let scaled_rate_incr = INTEREST_PER_SEC_RATE * U256::from(dt);
            let scaled_interest = scaled_outstanding * scaled_rate_incr;
            scaled_interest / SCALING_FACTOR
        };
        let expected_total = stored_debt + expected_interest;

        prop_assert_eq!(
            total_debt, expected_total,
            "accrued debt mismatch: contract={} formula={} (debt={}, interest={}, dt={})",
            total_debt, expected_total, stored_debt, expected_interest, dt,
        );

        // With dt > 0 and debt > 0, interest must be strictly positive.
        if dt > 0 && stored_debt > U256::ZERO {
            prop_assert!(
                expected_interest > U256::ZERO,
                "expected positive interest for dt={} debt={}",
                dt, stored_debt,
            );
        }

        // --- Repay the full outstanding debt ---
        vm.set_sender(recipient);
        mock_transfer_from(&vm, ARB_ADDR, recipient, contract_addr, total_debt);

        s.repay(ticket, total_debt).unwrap();

        // After full repayment at the same timestamp, debt should be zero.
        let post_repay_debt = s.debt_outstanding(ticket, t1).unwrap();
        prop_assert_eq!(
            post_repay_debt, U256::ZERO,
            "debt should be zero after full repayment, got {}",
            post_repay_debt,
        );
    }
}
