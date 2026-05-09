use alloy_sol_types::sol;

use stylus_sdk::{
    alloy_primitives::{Address, U256, U8},
    prelude::*,
    storage::{StorageAddress, StorageMap, StorageU256, StorageU8},
};

extern crate alloc;

sol! {
    event Transfer(
        address indexed from,
        address indexed to,
        uint256 value
    );
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
    event Deposit(
        address indexed sender,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );
    event Withdraw(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );
    error AlreadyCreated();
    error NotEnoughBal();
    error NotEnoughAllowance();
    error BelowCollateralRequirement();
    error CheckedUnderflow();
}

#[derive(SolidityError)]
pub enum Error {
    AlreadyCreated(AlreadyCreated),
    NotEnoughBal(NotEnoughBal),
    NotEnoughAllowance(NotEnoughAllowance),
    CheckedUnderflow(CheckedUnderflow),
}

// Scaling factor that's needed to be computed for the collateral requirement.
const SCALING_FACTOR: U256 = U256::from_limbs([1000, 0, 0, 0]);

// Collateral requirement minimum amount.
const COLLATERAL_REQ: U256 = U256::from_limbs([100, 0, 0, 0]);

const SECURITY_DEPOSIT_RATIO: U256 = U256::from_limbs([100, 0, 0, 0]);

#[storage]
#[entrypoint]
struct Storage {
    pub version: StorageU8,
    pub operator: StorageAddress,

    pub balance_of: StorageMap<Address, StorageU256>,
    pub allowance: StorageMap<Address, StorageMap<Address, StorageU256>>,

    pub total_assets: StorageU256,
    pub asset: StorageAddress,
    pub shares_erc20: StorageU256,
    pub total_shares: StorageU256,
}

#[public]
impl Storage {
    pub fn init(&mut self, operator: Address, asset: Address) -> Result<(), Error> {
        if !self.version.get().is_zero() {
            return Err(Error::AlreadyCreated(AlreadyCreated));
        }
        self.version.set(U8::from(1));
        self.operator.set(operator);
        self.asset.set(asset);
        Ok(())
    }

    /* ~~~~~~ ERC20 (share features): ~~~~~~ */

    pub fn name(&self) -> String {
        "Cluj Lending Shares".to_owned()
    }

    pub fn symbol(&self) -> String {
        "SCLUJ".to_owned()
    }

    pub fn decimals(&self) -> u8 {
        6
    }

    pub fn total_supply(&self) -> U256 {
        self.total_shares.get()
    }

    pub fn balance_of(&self, owner: Address) -> U256 {
        self.balance_of.get(owner)
    }

    pub fn allowance(&self, owner: Address, spender: Address) -> U256 {
        self.allowance.get(owner).get(spender)
    }

    pub fn approve(&mut self, spender: Address, value: U256) -> bool {
        let owner = self.vm().msg_sender();
        self.allowance.setter(owner).setter(spender).set(value);
        self.vm().log(Approval {
            owner,
            spender,
            value,
        });
        true
    }

    pub fn transfer(&mut self, to: Address, value: U256) -> Result<bool, Error> {
        self.internal_transfer_from(self.vm().msg_sender(), to, value)
            .map(|_| true)
    }

    pub fn transfer_from(
        &mut self,
        from: Address,
        to: Address,
        value: U256,
    ) -> Result<bool, Error> {
        let exp = self.allowance.getter(from).get(to);
        if value > exp {
            return Err(Error::NotEnoughAllowance(NotEnoughAllowance {}));
        }
        self.internal_transfer_from(from, to, value)?;
        if exp != U256::MAX {
            self.allowance
                .setter(from)
                .setter(to)
                .update_wrap_sub(value);
        }
        Ok(true)
    }

    /* ~~~~~~ LENDING: ~~~~~~ */

    pub fn borrow(&mut self, ausd_amt: U256, token_collateral: U256) -> Result<U256, Error> {
        if ausd_amt.is_zero() {
            return Err(Error::TooLowAusd(TooLowAusd {}));
        }
        if token_collateral.is_zero() {
            return Err(Error::ZeroTokenCollateral(ZeroTokenCollateral));
        }
        // Set aside the security deposit:
        let security_deposit = mul_div(ausd_amt, SECURITY_DEPOSIT_RATIO, SCALING_FACTOR);
        if security_deposit.is_zero() {
            return Err(Error::TooLowCollateral(TooLowCollateral {}));
        }
        let ausd_amt = ausd_amt - security_deposit;
        // Compute the utilisation rate that we need to enforce that they
        // don't borrow an unhealthy amount, after we've taken the
        // security deposit:
        let util_rate = (borrow_amt * SCALING_FACTOR) / token_amt;
        if COLLATERAL_REQ > util_rate {
            return Err(Error::BelowCollateralRequirement(
                BelowCollateralRequirement {},
            ));
        }
    }

    /* ~~~~~~ ERC4626: ~~~~~~ */

    pub fn asset(&self) -> Address {
        self.asset.get()
    }

    pub fn total_assets(&self) -> U256 {
        self.total_assets.get()
    }

    pub fn convert_to_shares(&self, assets: U256) -> U256 {
        todo!()
    }

    pub fn convert_to_assets(&self, shares: U256) -> U256 {
        todo!()
    }

    pub fn max_deposit(&self, receiver: Address) -> U256 {
        todo!()
    }

    pub fn deposit(&mut self, assets: U256, receiver: Address) -> U256 {
        todo!()
    }

    pub fn max_mint(&self, receiver: Address) -> U256 {
        todo!()
    }

    pub fn mint(&mut self, shares: U256, receiver: Address) -> U256 {
        todo!()
    }

    pub fn max_withdraw(&self, owner: Address) -> U256 {
        todo!()
    }

    pub fn withdraw(&mut self, assets: U256, receiver: Address, owner: Address) -> U256 {
        todo!()
    }

    pub fn max_redeem(&self, owner: Address) -> U256 {
        todo!()
    }

    pub fn redeem(&mut self, shares: U256, receiver: Address, owner: Address) -> U256 {
        todo!()
    }
}

impl Storage {
    pub fn internal_transfer_from(
        &mut self,
        sender: Address,
        recipient: Address,
        value: U256,
    ) -> Result<(), Error> {
        self.balance_of
            .setter(sender)
            .update_check_sub(value)
            .ok_or(Error::NotEnoughBal(NotEnoughBal))?;
        self.balance_of.setter(sender).update_wrap_add(value);
        Ok(())
    }
}

fn mul_div(x: U256, y: U256, z: U256) -> U256 {
    // TODO: make this the actual muldiv instead of this:
    (x * y) / z
}
