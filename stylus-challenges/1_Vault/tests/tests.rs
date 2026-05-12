use proptest::prelude::*;

use stylus_sdk::{
    alloy_primitives::{Address, U256},
    alloy_sol_types::{sol, SolCall},
    testing::*,
};

use cluj_vault::*;

sol! {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

fn abi_true() -> Vec<u8> {
    U256::from(1).to_be_bytes::<32>().to_vec()
}

fn abi_u256(v: U256) -> Vec<u8> {
    v.to_be_bytes::<32>().to_vec()
}

fn mock_balance_of(vm: &TestVM, tok: Address, account: Address, bal: U256) {
    let data = balanceOfCall { account }.abi_encode();
    vm.mock_call(tok, data, U256::ZERO, Ok(abi_u256(bal)));
}

fn mock_transfer_from(vm: &TestVM, tok: Address, from: Address, to: Address, amt: U256) {
    let data = transferFromCall { from, to, amount: amt }.abi_encode();
    vm.mock_call(tok, data, U256::ZERO, Ok(abi_true()));
}

fn mock_transfer(vm: &TestVM, tok: Address, to: Address, amt: U256) {
    let data = transferCall { to, amount: amt }.abi_encode();
    vm.mock_call(tok, data, U256::ZERO, Ok(abi_true()));
}

fn arb_addr() -> impl Strategy<Value = Address> {
    prop::array::uniform20(1u8..=255u8).prop_map(Address::from)
}

/// Generate 1..8 depositors with amounts 1..10_000 each.
fn arb_depositors() -> impl Strategy<Value = Vec<(Address, u64)>> {
    prop::collection::vec(
        (arb_addr(), 1u64..10_000),
        1..=8,
    )
}

proptest! {
    #[test]
    fn no_bankruptcy_on_fractional_withdraw(
        tok in arb_addr(),
        depositors in arb_depositors(),
    ) {
        let vm = TestVM::new();
        let vault_addr = vm.contract_address();
        let mut s = TokenVault::from(&vm);

        // Init vault with the ERC20.
        vm.set_sender(Address::from([0x01; 20]));
        s.init(tok).unwrap();

        // Track the vault's real balance ourselves.
        let mut vault_balance: u128 = 0;

        // Deduplicate depositors by address (later ones overwrite).
        let mut seen = std::collections::HashMap::<Address, u64>::new();
        for (addr, amt) in &depositors {
            // skip if addr == tok or vault_addr to avoid confusion
            if *addr == tok || *addr == vault_addr { continue; }
            seen.insert(*addr, *amt);
        }
        let unique: Vec<(Address, u64)> = seen.into_iter().collect();
        prop_assume!(!unique.is_empty());

        // === Deposit phase ===
        for (addr, amt_raw) in &unique {
            let amt = U256::from(*amt_raw);

            // Only mock balanceOf when total_shares > 0 — the first deposit
            // takes the `else` branch (shares = amount) and never calls
            // balanceOf.  Registering an unused mock here would poison the
            // FIFO queue and make the withdrawal-phase balanceOf return 0.
            if vault_balance > 0 {
                mock_balance_of(&vm, tok, vault_addr, U256::from(vault_balance));
            }
            // Mock the transferFrom that deposit_tokens will call.
            mock_transfer_from(&vm, tok, *addr, vault_addr, amt);

            vm.set_sender(*addr);
            let shares = s.deposit_tokens(amt).unwrap();
            prop_assert!(shares > U256::ZERO, "deposit should yield >0 shares");

            // The transferFrom succeeded so vault balance goes up.
            vault_balance += *amt_raw as u128;
        }

        // === Withdraw phase ===
        // Every depositor withdraws ALL their shares.
        let mut total_withdrawn: u128 = 0;

        for (addr, _) in &unique {
            let shares = s.shares_of(*addr);
            if shares == U256::ZERO { continue; }

            // Mock balanceOf(vault) with current vault_balance.
            mock_balance_of(&vm, tok, vault_addr, U256::from(vault_balance));

            // Calculate what the contract will send: (shares * vault_balance) / total_shares
            let total_shares = s.total_shares();
            let payout = (shares * U256::from(vault_balance)) / total_shares;

            // Mock the transfer the contract will do.
            mock_transfer(&vm, tok, *addr, payout);

            vm.set_sender(*addr);
            let amount = s.withdraw_tokens(shares).unwrap();

            let amount_u128: u128 = amount.try_into().unwrap();

            // INVARIANT: payout must not exceed vault balance.
            prop_assert!(
                amount_u128 <= vault_balance,
                "bankrupt! tried to send {} but vault only has {}",
                amount_u128, vault_balance,
            );

            vault_balance -= amount_u128;
            total_withdrawn += amount_u128;
        }

        // After all withdrawals, total_shares should be zero.
        prop_assert_eq!(
            s.total_shares(), U256::ZERO,
            "all shares should be burned after full withdrawal"
        );

        // Total withdrawn should not exceed total deposited.
        let total_deposited: u128 = unique.iter().map(|(_, a)| *a as u128).sum();
        prop_assert!(
            total_withdrawn <= total_deposited,
            "withdrew {} but only deposited {}",
            total_withdrawn, total_deposited,
        );

        // Any dust left is rounding from integer division — acceptable as
        // long as vault_balance >= 0 (which is guaranteed by the no-bankruptcy
        // check above) and total_withdrawn <= total_deposited.
    }
}
