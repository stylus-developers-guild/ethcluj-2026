use proptest::prelude::*;

use stylus_sdk::{
    alloy_primitives::{Address, Bytes, U256, U64},
    alloy_sol_types::{sol, SolCall},
    testing::*,
};

use cluj_email::*;

sol! {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

fn abi_true() -> Vec<u8> {
    U256::from(1).to_be_bytes::<32>().to_vec()
}

fn mock_transfer_from(vm: &TestVM, tok: Address, from: Address, to: Address, amt: U256) {
    let data = transferFromCall {
        from,
        to,
        amount: amt,
    }
    .abi_encode();
    vm.mock_call(tok, data, U256::ZERO, Ok(abi_true()));
}

fn mock_transfer(vm: &TestVM, tok: Address, to: Address, amt: U256) {
    let data = transferCall { to, amount: amt }.abi_encode();
    vm.mock_call(tok, data, U256::ZERO, Ok(abi_true()));
}

/// Configure epoch + enable a token for recipient.
fn setup(
    vm: &TestVM,
    s: &mut Storage,
    epoch: u64,
    recip: Address,
    tok: Address,
    ask: U256,
) {
    vm.set_block_timestamp(epoch + 1);
    s.ts_epoch.set(U64::from(epoch));
    vm.set_sender(recip);
    s.enable_token(tok, ask).unwrap();
}

fn arb_addr() -> impl Strategy<Value = Address> {
    prop::array::uniform20(1u8..=255u8).prop_map(Address::from)
}

fn arb_word_email() -> impl Strategy<Value = WordEmail> {
    (
        arb_addr(),
        1u32..=u32::MAX,
        any::<u32>(),
        prop_oneof![Just(EmailStatus::RECEIVED), Just(EmailStatus::REFUNDED)],
    )
        .prop_map(|(r, t, ts, st)| WordEmail {
            refund_recipient: r,
            token_id: t,
            ts_after_epoch: ts,
            status: st,
        })
}

proptest! {
    #[test]
    fn e2e_send_and_read(
        recip in arb_addr(),
        sender in arb_addr(),
        tok in arb_addr(),
        ask_raw in 1u64..1_000_000,
        epoch in 1_000_000u64..2_000_000,
        dt in 1u64..100_000,
    ) {
        prop_assume!(sender != recip && tok != recip && tok != sender);
        let ask = U256::from(ask_raw);
        let vm = TestVM::new();
        let ca = vm.contract_address();
        let mut s = Storage::from(&vm);
        setup(&vm, &mut s, epoch, recip, tok, ask);

        // send
        vm.set_block_timestamp(epoch + dt);
        vm.set_sender(sender);
        mock_transfer_from(&vm, tok, sender, ca, ask);
        let paid = s.send_email(recip, sender, tok, ask, Bytes::from(vec![1]));
        prop_assert!(paid.is_ok(), "{:?}", paid);
        prop_assert_eq!(paid.unwrap(), ask);
        prop_assert!(!vm.get_emitted_logs().is_empty());

        // read
        vm.set_block_timestamp(epoch + dt + 100);
        vm.set_sender(recip);
        let dest = Address::from([0xBB; 20]);
        mock_transfer(&vm, tok, dest, ask);
        let (addrs, amts) = s.read_email(dest).unwrap();
        prop_assert_eq!(&addrs, &[tok]);
        prop_assert_eq!(&amts, &[ask]);
    }

    #[test]
    fn e2e_multi_send_read(
        recip in arb_addr(),
        tok in arb_addr(),
        ask_raw in 1u64..100_000,
        epoch in 1_000_000u64..2_000_000,
        n in 1u32..10,
    ) {
        prop_assume!(tok != recip);
        let ask = U256::from(ask_raw);
        let vm = TestVM::new();
        let ca = vm.contract_address();
        let mut s = Storage::from(&vm);
        setup(&vm, &mut s, epoch, recip, tok, ask);

        let mut sent = 0u32;
        for i in 0..n {
            let sb = {
                let mut b = [0u8; 20]; b[0] = (i as u8).wrapping_add(1); b[1] = 0xAA; b
            };
            let sender = Address::from(sb);
            if sender == recip || sender == tok { continue; }
            vm.set_block_timestamp(epoch + 1000 + i as u64);
            vm.set_sender(sender);
            mock_transfer_from(&vm, tok, sender, ca, ask);
            prop_assert!(s.send_email(recip, sender, tok, ask, Bytes::from(vec![i as u8])).is_ok());
            sent += 1;
        }
        if sent == 0 { return Ok(()); }

        vm.set_block_timestamp(epoch + 100_000);
        vm.set_sender(recip);
        let dest = Address::from([0xCC; 20]);
        for _ in 0..sent { mock_transfer(&vm, tok, dest, ask); }
        let (addrs, amts) = s.read_email(dest).unwrap();
        prop_assert_eq!(addrs.len(), sent as usize);
        prop_assert!(addrs.iter().all(|a| *a == tok));
        prop_assert!(amts.iter().all(|a| *a == ask));

        // second read yields nothing
        let (a2, m2) = s.read_email(dest).unwrap();
        prop_assert!(a2.is_empty() && m2.is_empty());
    }

    #[test]
    fn e2e_refund(
        recip in arb_addr(), sender in arb_addr(), tok in arb_addr(),
        ask_raw in 1u64..1_000_000,
        epoch in 1_000_000u64..2_000_000,
        dt in 1u64..100_000,
    ) {
        prop_assume!(sender != recip && tok != recip && tok != sender);
        let ask = U256::from(ask_raw);
        let vm = TestVM::new();
        let ca = vm.contract_address();
        let mut s = Storage::from(&vm);
        setup(&vm, &mut s, epoch, recip, tok, ask);

        // send
        let send_ts = epoch + dt;
        vm.set_block_timestamp(send_ts);
        vm.set_sender(sender);
        mock_transfer_from(&vm, tok, sender, ca, ask);
        prop_assert!(s.send_email(recip, sender, tok, ask, Bytes::from(vec![0xAA])).is_ok());

        // too early → refund must fail
        vm.set_block_timestamp(send_ts + UNREAD_WINDOW);
        prop_assert!(s.refund(recip, 0).is_err());

        // past deadline → refund succeeds
        vm.set_block_timestamp(send_ts + UNREAD_WINDOW + 1);
        mock_transfer(&vm, tok, sender, ask);
        let amt = s.refund(recip, 0).unwrap();
        prop_assert_eq!(amt, ask);

        // double refund fails
        prop_assert!(s.refund(recip, 0).is_err());
    }

    #[test]
    fn e2e_refund_skips_on_read(
        recip in arb_addr(), sender in arb_addr(), tok in arb_addr(),
        ask_raw in 1u64..100_000,
        epoch in 1_000_000u64..2_000_000,
    ) {
        prop_assume!(sender != recip && tok != recip && tok != sender);
        let ask = U256::from(ask_raw);
        let vm = TestVM::new();
        let ca = vm.contract_address();
        let mut s = Storage::from(&vm);
        setup(&vm, &mut s, epoch, recip, tok, ask);

        // send 3 emails
        for i in 0u64..3 {
            vm.set_block_timestamp(epoch + 1000 + i);
            vm.set_sender(sender);
            mock_transfer_from(&vm, tok, sender, ca, ask);
            prop_assert!(s.send_email(recip, sender, tok, ask, Bytes::from(vec![i as u8])).is_ok());
        }

        // refund middle one (index 1)
        vm.set_block_timestamp(epoch + 1001 + UNREAD_WINDOW + 1);
        vm.set_sender(sender);
        mock_transfer(&vm, tok, sender, ask);
        prop_assert!(s.refund(recip, 1).is_ok());

        // read → only 2 emails paid out
        vm.set_sender(recip);
        let dest = Address::from([0xDD; 20]);
        mock_transfer(&vm, tok, dest, ask);
        mock_transfer(&vm, tok, dest, ask);
        let (addrs, _) = s.read_email(dest).unwrap();
        prop_assert_eq!(addrs.len(), 2);
    }

    #[test]
    fn err_too_backed_up(
        recip in arb_addr(), sender in arb_addr(), tok in arb_addr(),
        epoch in 1_000_000u64..2_000_000,
    ) {
        prop_assume!(sender != recip && tok != recip && tok != sender);
        let ask = U256::from(1u64);
        let vm = TestVM::new();
        let ca = vm.contract_address();
        let mut s = Storage::from(&vm);
        setup(&vm, &mut s, epoch, recip, tok, ask);

        for i in 0..=(MAX_UNREAD_EMAILS + 1) {
            vm.set_block_timestamp(epoch + 100 + i as u64);
            vm.set_sender(sender);
            mock_transfer_from(&vm, tok, sender, ca, ask);
            let r = s.send_email(recip, sender, tok, ask, Bytes::from(vec![i as u8]));
            if i == MAX_UNREAD_EMAILS + 1 {
                prop_assert!(r.is_err());
            } else {
                prop_assert!(r.is_ok(), "email {} failed: {:?}", i, r);
            }
        }
    }

    #[test]
    fn err_refund_oob(recip in arb_addr(), epoch in 1_000_000u64..2_000_000) {
        let vm = TestVM::new();
        let mut s = Storage::from(&vm);
        s.ts_epoch.set(U64::from(epoch));
        vm.set_block_timestamp(epoch + UNREAD_WINDOW + 1000);
        prop_assert!(s.refund(recip, 0).is_err());
        prop_assert!(s.refund(recip, 9999).is_err());
    }
}
