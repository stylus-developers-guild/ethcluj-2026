#![cfg_attr(not(any(test, feature = "export-abi")), no_main)]
extern crate alloc;

use alloy_primitives::{Address, U256};
use alloy_sol_types::{sol, SolError};
use stylus_sdk::{
    prelude::*,
    storage::{StorageAddress, StorageMap, StorageU256},
};

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
    error AlreadyInitialized();
    error InsufficientShares(address user, uint256 available, uint256 requested);
    error ZeroAmount();
}

#[public]
impl TokenVault {
    pub fn init(&mut self, token_addr: Address) -> Result<(), Vec<u8>> {
        if self.token.get() != Address::ZERO {
            return Err(AlreadyInitialized {}.abi_encode());
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

    pub fn deposit_tokens(&mut self, amount: U256) -> Result<(), Vec<u8>> {
        if amount == U256::ZERO {
            return Err(ZeroAmount {}.abi_encode());
        }

        let token_addr = self.token.get();
        let token = IERC20::new(token_addr);
        let vault_addr = self.vm().contract_address();
        let caller = self.vm().msg_sender();

        let shares: U256;
        let current_total = self.total_shares.get();

        if current_total == U256::ZERO {
            shares = amount;
        } else {
            let vault_balance = token.balance_of(self.vm(), Call::new(), vault_addr)?;
            shares = (amount * current_total) / vault_balance;
        }

        self.mint_shares(caller, shares);

        let config = Call::new_mutating(self);
        token.transfer_from(self.vm(), config, caller, vault_addr, amount)?;

        self.vm().log(Deposit {
            user: caller,
            amount,
            shares,
        });

        Ok(())
    }

    pub fn withdraw_tokens(&mut self, shares: U256) -> Result<(), Vec<u8>> {
        if shares == U256::ZERO {
            return Err(ZeroAmount {}.abi_encode());
        }

        let token_addr = self.token.get();
        let token = IERC20::new(token_addr);
        let vault_addr = self.vm().contract_address();
        let caller = self.vm().msg_sender();

        let vault_balance = token.balance_of(self.vm(), Call::new(), vault_addr)?;
        let current_total = self.total_shares.get();
        let amount = (shares * vault_balance) / current_total;

        self.burn_shares(caller, shares)?;

        let config = Call::new_mutating(self);
        token.transfer(self.vm(), config, caller, amount)?;

        self.vm().log(Withdraw {
            user: caller,
            shares,
            amount,
        });

        Ok(())
    }
}

impl TokenVault {
    fn mint_shares(&mut self, to: Address, amount: U256) {
        let new_total = self.total_shares.get() + amount;
        self.total_shares.set(new_total);
        let new_balance = self.shares_of.get(to) + amount;
        self.shares_of.setter(to).set(new_balance);
    }

    fn burn_shares(&mut self, from: Address, amount: U256) -> Result<(), Vec<u8>> {
        let current = self.shares_of.get(from);
        if current < amount {
            return Err(InsufficientShares {
                user: from,
                available: current,
                requested: amount,
            }
            .abi_encode());
        }
        self.shares_of.setter(from).set(current - amount);
        let new_total = self.total_shares.get() - amount;
        self.total_shares.set(new_total);
        Ok(())
    }
}
