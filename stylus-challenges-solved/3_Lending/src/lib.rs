// Simple lending protocol, working with a single asset. Should NOT be
// used in production (no muldiv, no safety).

#![cfg_attr(not(any(test, feature = "export-abi")), no_main)]
extern crate alloc;

use stylus_sdk::{alloy_primitives::*, prelude::*, storage::*};

use alloc::vec::Vec;

pub mod error;
pub mod immutables;

use crate::{
    error::Error,
    immutables::{
        ARB_ADDR, COLLATERAL_REQ, INTEREST_PER_SEC_RATE, SCALING_FACTOR, SECURITY_DEPOSIT,
    },
};

sol_interface! {
    interface IERC20 {
        function transfer(address to, uint256 amount) external returns (bool);
        function transferFrom(address from, address to, uint256 amount) external returns (bool);
        function mint(address to, uint256 amount) external;
        function burn(address from, uint256 amount) external;
    }
}

macro_rules! assert_or {
    ($cond:expr, $err:expr) => {
        if !($cond) {
            return Err($err);
        }
    };
}

#[storage]
pub struct StorageTimepoint {
    /// The latest timestamp.
    pub time: StorageU256,
    /// Interest accumulated, scaled by the scaling factor.
    pub interest: StorageU256,
}

#[storage]
#[entrypoint]
pub struct Storage {
    /// Was this contract set up properly?
    created: StorageU256,

    /// Token that we're associated with.
    token_addr: StorageAddress,

    /// The collateral that's okay to use for redemption.
    token_for_redemption: StorageU256,

    /// Supply of the connected token, stored here to avoid an excessive call.
    pub cash_supply: StorageU256,

    /// Borrow count for the ticket increment.
    pub borrow_count: StorageU256,

    /// Borrow timepoints made against the identifier.
    pub borrows: StorageMap<U256, StorageVec<StorageTimepoint>>,

    /// Owners of the tickets floating around in the system.
    pub ticket_owners: StorageMap<U256, StorageAddress>,

    /// Collateral supplied by the identifier.
    pub collateral: StorageMap<U256, StorageU256>,

    /// Debt minted by the identifier given.
    pub debt: StorageMap<U256, StorageU256>,

    /// Amount of cash set aside for a bad debt situation.
    pub security_deposits: StorageU256,
}

#[public]
impl Storage {
    pub fn ctor(&mut self, token: Address) -> Result<(), Error> {
        assert_or!(
            self.created.get().is_zero(),
            Error::AlreadyInitialised(error::AlreadyInitialised {})
        );
        self.token_addr.set(token);
        self.created.set(U256::from(1));
        Ok(())
    }

    /// Return the utilisation rate, scaled by the scaling factor.
    pub fn utilisation_rate(borrowed: U256, cash: U256) -> U256 {
        borrowed / cash
    }

    pub fn borrow(
        &mut self,
        ausd_amt: U256,
        token_collateral: U256,
        recipient: Address,
    ) -> Result<U256, Error> {
        let sender = self.vm().msg_sender();
        let this = self.vm().contract_address();
        let arb = IERC20::new(ARB_ADDR);
        let config = Call::new_mutating(self);
        arb.transfer_from(self.vm(), config, sender, this, token_collateral)
            .map_err(|e| {
                let e: Vec<u8> = e.into();
                Error::ERC20Failed(error::ERC20Failed {
                    reason: Bytes::from(e),
                })
            })?;
        let cur_time = self.vm().block_timestamp();
        let ticket = self.internal_borrow(cur_time, ausd_amt, token_collateral)?;
        self.ticket_owners.setter(ticket).set(recipient);
        let token_addr = self.token_addr.get();
        let token = IERC20::new(token_addr);
        let config = Call::new_mutating(self);
        token
            .mint(self.vm(), config, recipient, ausd_amt)
            .map_err(|e| {
                let e: Vec<u8> = e.into();
                Error::ERC20Failed(error::ERC20Failed {
                    reason: Bytes::from(e),
                })
            })?;
        Ok(ticket)
    }

    pub fn debt_outstanding(&mut self, ticket: U256, cur_time: u64) -> Result<U256, Error> {
        let (_, timepoint_interest) = self.internal_record_timepoint(ticket, cur_time)?;
        Ok(self.debt.getter(ticket).get() + timepoint_interest)
    }

    pub fn liquidate(&mut self, ticket: U256) -> Result<(), Error> {
        self.internal_liquidate(ticket, self.vm().block_timestamp())
    }

    pub fn repay(&mut self, ticket: U256, token_repay: U256) -> Result<(), Error> {
        let sender = self.vm().msg_sender();
        assert_or!(
            self.ticket_owners.getter(ticket).get() == sender,
            Error::NotOwner(error::NotOwner {})
        );
        let this = self.vm().contract_address();
        let arb = IERC20::new(ARB_ADDR);
        let config = Call::new_mutating(self);
        arb.transfer_from(self.vm(), config, sender, this, token_repay)
            .map_err(|e| {
                let e: Vec<u8> = e.into();
                Error::ERC20Failed(error::ERC20Failed {
                    reason: Bytes::from(e),
                })
            })?;
        self.internal_repay(ticket, self.vm().block_timestamp(), token_repay)?;
        Ok(())
    }

    pub fn redeem(&mut self, cash: U256, recipient: Address) -> Result<U256, Error> {
        let sender = self.vm().msg_sender();
        let this = self.vm().contract_address();
        let token_addr = self.token_addr.get();
        let token = IERC20::new(token_addr);
        let config = Call::new_mutating(self);
        token
            .transfer_from(self.vm(), config, sender, this, cash)
            .map_err(|e| {
                let e: Vec<u8> = e.into();
                Error::ERC20Failed(error::ERC20Failed {
                    reason: Bytes::from(e),
                })
            })?;
        let config = Call::new_mutating(self);
        token.burn(self.vm(), config, this, cash).map_err(|e| {
            let e: Vec<u8> = e.into();
            Error::ERC20Failed(error::ERC20Failed {
                reason: Bytes::from(e),
            })
        })?;
        let redeemed = self.internal_redeem(cash)?;
        let arb = IERC20::new(ARB_ADDR);
        let config = Call::new_mutating(self);
        arb.transfer(self.vm(), config, recipient, redeemed)
            .map_err(|e| {
                let e: Vec<u8> = e.into();
                Error::ERC20Failed(error::ERC20Failed {
                    reason: Bytes::from(e),
                })
            })?;
        Ok(redeemed)
    }
}

impl Storage {
    fn internal_liquidate(&mut self, ticket: U256, cur_time: u64) -> Result<(), Error> {
        let (_, timepoint_interest) = self.internal_record_timepoint(ticket, cur_time)?;
        let debt_outstanding = self.debt.getter(ticket).get() + timepoint_interest;
        let scaled_debt_outstanding = debt_outstanding * SCALING_FACTOR;
        let token_collateral = self.collateral.getter(ticket).get();
        let scaled_token_collateral = token_collateral * SCALING_FACTOR;
        let utilisation = Self::utilisation_rate(scaled_debt_outstanding, scaled_token_collateral);
        assert_or!(
            utilisation >= COLLATERAL_REQ,
            Error::NotAbleToLiquidate(error::NotAbleToLiquidate {})
        );
        self.debt.setter(ticket).set(U256::ZERO);
        let collateral_diff = token_collateral - debt_outstanding;
        self.security_deposits
            .set(if collateral_diff > self.security_deposits.get() {
                U256::ZERO
            } else {
                token_collateral - debt_outstanding
            });
        self.collateral.setter(ticket).set(U256::ZERO);
        self.debt.setter(ticket).set(U256::ZERO);
        let tickets_len = self.borrows.getter(ticket).len();
        // Override the timepoint we just set using the grow function.
        self.borrows
            .setter(ticket)
            .setter(tickets_len - 1)
            .unwrap()
            .interest
            .set(U256::ZERO);
        Ok(())
    }

    fn internal_repay(
        &mut self,
        ticket: U256,
        cur_time: u64,
        token_repay: U256,
    ) -> Result<(), Error> {
        let (_, timepoint_interest) = self.internal_record_timepoint(ticket, cur_time)?;
        let borrows_len = self.borrows.getter(ticket).len();
        let mut leftover = token_repay;
        if timepoint_interest > leftover {
            self.borrows
                .setter(ticket)
                .setter(borrows_len - 1)
                .unwrap()
                .interest
                .set(timepoint_interest - leftover);
            return Ok(());
        } else {
            self.borrows
                .setter(ticket)
                .setter(borrows_len - 1)
                .unwrap()
                .interest
                .set(U256::ZERO);
            leftover -= timepoint_interest;
        };
        let outstanding_debt = self.debt.getter(ticket).get();
        if outstanding_debt > leftover {
            self.debt.setter(ticket).set(outstanding_debt - leftover);
        } else {
            self.debt.setter(ticket).set(U256::ZERO)
        };
        Ok(())
    }

    /// Record a new timepoint, assuming that it exists.
    fn internal_record_timepoint(
        &mut self,
        ticket: U256,
        cur_time: u64,
    ) -> Result<(U256, U256), Error> {
        let cur_time = U256::from(cur_time);
        let borrows = self.borrows.getter(ticket);
        let last_timepoint = borrows
            .getter(self.borrows.getter(ticket).len() - 1)
            .unwrap();
        if last_timepoint.time.get() == cur_time {
            return Ok((last_timepoint.time.get(), last_timepoint.interest.get()));
        }
        let scaled_outstanding_debt =
            (self.debt.getter(ticket).get() + last_timepoint.interest.get()) * SCALING_FACTOR;
        let scaled_interest_pct_incr =
            INTEREST_PER_SEC_RATE * (cur_time - last_timepoint.time.get());
        let scaled_interest = scaled_outstanding_debt * scaled_interest_pct_incr;
        let mut borrows = self.borrows.setter(ticket);
        let mut timepoint = borrows.grow();
        timepoint.time.set(cur_time);
        let interest = scaled_interest / SCALING_FACTOR;
        timepoint.interest.set(interest);
        Ok((cur_time, interest))
    }

    fn internal_redeem(&mut self, cash: U256) -> Result<U256, Error> {
        let scaled_token_for_redemption = self.token_for_redemption.get() * SCALING_FACTOR;
        let scaled_cash = cash * SCALING_FACTOR;
        let scaled_cash_supply = self.cash_supply.get() * SCALING_FACTOR;
        let token_amt = scaled_token_for_redemption * (scaled_cash / scaled_cash_supply);
        Ok(token_amt / SCALING_FACTOR)
    }

    fn internal_borrow(
        &mut self,
        cur_time: u64,
        ausd_amt: U256,
        token_collateral: U256,
    ) -> Result<U256, Error> {
        let ticket = self.borrow_count.get();
        self.borrow_count.set(ticket + U256::from(1));
        let mut scaled_ausd_amt = ausd_amt * SCALING_FACTOR;
        let mut scaled_token_collateral = token_collateral * SCALING_FACTOR;
        let is_underutilised =
            Self::utilisation_rate(scaled_ausd_amt, scaled_token_collateral) < COLLATERAL_REQ;
        assert_or!(
            is_underutilised,
            Error::BadBorrowAttempt(error::BadBorrowAttempt {})
        );
        let mut scaled_redemption_amt = scaled_token_collateral
            .checked_mul(
                scaled_ausd_amt
                    .checked_div(scaled_token_collateral)
                    .ok_or(Error::CheckedDiv(error::CheckedDiv {}))?,
            )
            .ok_or(Error::CheckedMul(error::CheckedMul {}))?;
        scaled_redemption_amt = scaled_redemption_amt
            .checked_sub(scaled_redemption_amt * SECURITY_DEPOSIT)
            .ok_or(Error::CheckedSub(error::CheckedSub {}))?;
        let redemption_amt = scaled_redemption_amt / SCALING_FACTOR;
        self.token_for_redemption.set(
            self.token_for_redemption
                .get()
                .checked_add(redemption_amt)
                .ok_or(Error::CheckedAdd(error::CheckedAdd {}))?,
        );
        let scaled_ausd_security_deposit = scaled_ausd_amt * SECURITY_DEPOSIT;
        let ausd_security_deposit = scaled_ausd_security_deposit / SCALING_FACTOR;
        let scaled_token_security_deposit = scaled_token_collateral * SECURITY_DEPOSIT;
        scaled_ausd_amt -= scaled_ausd_security_deposit;
        scaled_token_collateral -= scaled_token_security_deposit;
        self.security_deposits.set(
            self.security_deposits
                .get()
                .checked_add(ausd_security_deposit)
                .ok_or(Error::CheckedAdd(error::CheckedAdd {}))?,
        );
        // We have to scale this again so we correctly get the amount
        // adjusted for the security deposit.
        let ausd_amt = scaled_ausd_amt / SCALING_FACTOR;
        self.cash_supply.set(
            self.cash_supply
                .get()
                .checked_add(ausd_amt)
                .ok_or(Error::CheckedAdd(error::CheckedAdd {}))?,
        );
        let mut borrows = self.borrows.setter(ticket);
        let mut timepoint = borrows.grow();
        timepoint.time.set(U256::from(cur_time));
        // Interest in the timepoint should be set to 0 by default.
        let token_collateral = scaled_token_collateral / SCALING_FACTOR;
        self.collateral.setter(ticket).set(token_collateral);
        self.debt.setter(ticket).set(ausd_amt);
        Ok(ticket)
    }
}
