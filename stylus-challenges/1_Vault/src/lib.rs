#![cfg_attr(not(any(test, feature = "export-abi")), no_main)]
#![no_std]

use stylus_sdk::{
    alloy_primitives::{Address, Bytes, U256},
    alloy_sol_types::sol,
    prelude::*,
    storage::{StorageAddress, StorageMap, StorageU256},
};

extern crate alloc;

use alloc::{vec, vec::Vec};

sol_interface! {
    interface IERC20 {
        function balanceOf(address account) external view returns (uint256);
        function transfer(address to, uint256 amount) external returns (bool);
        function transferFrom(address from, address to, uint256 amount) external returns (bool);
    }
}

#[storage]
#[entrypoint]
pub struct TokenVault {
    token: StorageAddress,
    total_shares: StorageU256,
    shares_of: StorageMap<Address, StorageU256>,
}

sol! {
    event Deposit(address indexed user, uint256 amount, uint256 shares);
    event Withdraw(address indexed user, uint256 shares, uint256 amount);
    error AlreadyInitialised();
    error InsufficientShares(address user, uint256 available, uint256 requested);
    error ZeroAmount();
    error BalanceOf(bytes);
    error TransferFrom(bytes);
    error BurnShares(bytes);
    error Transfer(bytes);
}

#[derive(Clone, SolidityError)]
pub enum Error {
    AlreadyInitialised(AlreadyInitialised),
    InsufficientShares(InsufficientShares),
    ZeroAmount(ZeroAmount),
    BalanceOf(BalanceOf),
    TransferFrom(TransferFrom),
    BurnShares(BurnShares),
    Transfer(Transfer),
}

impl core::fmt::Debug for Error {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self {
            Self::AlreadyInitialised(_) => write!(f, "AlreadyInitialised"),
            Self::InsufficientShares(_) => write!(f, "InsufficientShares"),
            Self::ZeroAmount(_) => write!(f, "ZeroAmount"),
            Self::BalanceOf(_) => write!(f, "BalanceOf",),
            Self::TransferFrom(_) => write!(f, "TransferFrom",),
            Self::BurnShares(_) => write!(f, "BurnShares",),
            Self::Transfer(_) => write!(f, "Transfer",),
        }
    }
}

#[public]
impl TokenVault {
    pub fn init(&mut self, token_addr: Address) -> Result<(), Error> {
        if self.token.get() != Address::ZERO {
            return Err(Error::AlreadyInitialised(AlreadyInitialised {}));
        }
        self.token.set(token_addr);
        Ok(())
    }

    pub fn token(&self) -> Address {
        self.token.get()
    }

    pub fn total_shares(&self) -> U256 {
        self.total_shares.get()
    }

    pub fn shares_of(&self, who: Address) -> U256 {
        self.shares_of.get(who)
    }

    pub fn deposit_tokens(&mut self, amount: U256) -> Result<U256, Error> {
        if amount.is_zero() {
            return Err(Error::ZeroAmount(ZeroAmount {}));
        }
        let token_addr = self.token.get();
        let token = IERC20::new(token_addr);
        let vault_addr = self.vm().contract_address();
        let caller = self.vm().msg_sender();
        let current_total = self.total_shares.get();
        let shares = if current_total > U256::ZERO {
            let vault_balance = token
                .balance_of(self.vm(), Call::new(), vault_addr)
                .map_err(|b| Error::BalanceOf(BalanceOf(stylus_err_to_bytes(b))))?;
            (amount * current_total) / vault_balance
        } else {
            amount
        };
        self.mint_shares(caller, shares);
        let config = Call::new_mutating(self);
        token
            .transfer_from(self.vm(), config, caller, vault_addr, amount)
            .map_err(|b| Error::TransferFrom(TransferFrom(stylus_err_to_bytes(b))))?;
        self.vm().log(Deposit {
            user: caller,
            amount,
            shares,
        });
        Ok(shares)
    }

    pub fn withdraw_tokens(&mut self, shares: U256) -> Result<U256, Error> {
        todo!()
    }
}

fn stylus_err_to_bytes<T: Into<Vec<u8>>>(b: T) -> Bytes {
    Bytes::from(b.into())
}

impl TokenVault {
    fn mint_shares(&mut self, to: Address, amount: U256) {
        let new_total = self.total_shares.get() + amount;
        self.total_shares.set(new_total);
        let new_balance = self.shares_of.get(to) + amount;
        self.shares_of.setter(to).set(new_balance);
    }

    fn burn_shares(&mut self, from: Address, amount: U256) -> Result<(), Error> {
        let current = self.shares_of.get(from);
        if amount > current {
            return Err(Error::InsufficientShares(InsufficientShares {
                user: from,
                available: current,
                requested: amount,
            }));
        }
        self.shares_of.setter(from).set(current - amount);
        let new_total = self.total_shares.get() - amount;
        self.total_shares.set(new_total);
        Ok(())
    }
}
