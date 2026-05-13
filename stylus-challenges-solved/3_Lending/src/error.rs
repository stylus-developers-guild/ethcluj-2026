use alloy_sol_types::sol;
use stylus_sdk::prelude::*;

sol! {
    error AlreadyInitialised();
    error BadBorrowAttempt();
    error NotAbleToLiquidate();
    error NotOwner();
    error CheckedUnderflow();
    error CheckedOverflow();
    error CheckedMul();
    error CheckedDiv();
    error CheckedSub();
    error CheckedAdd();
    error ERC20Failed(bytes reason);
}

#[derive(SolidityError)]
pub enum Error {
    AlreadyInitialised(AlreadyInitialised),
    BadBorrowAttempt(BadBorrowAttempt),
    NotAbleToLiquidate(NotAbleToLiquidate),
    NotOwner(NotOwner),
    CheckedUnderflow(CheckedUnderflow),
    CheckedOverflow(CheckedOverflow),
    CheckedMul(CheckedMul),
    CheckedDiv(CheckedDiv),
    CheckedSub(CheckedSub),
    CheckedAdd(CheckedAdd),
    ERC20Failed(ERC20Failed),
}

impl core::fmt::Debug for Error {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self {
            Error::AlreadyInitialised(_) => write!(f, "AlreadyInitialised"),
            Error::BadBorrowAttempt(_) => write!(f, "BadBorrowAttempt"),
            Error::NotAbleToLiquidate(_) => write!(f, "NotAbleToLiquidate"),
            Error::NotOwner(_) => write!(f, "NotOwner"),
            Error::CheckedUnderflow(_) => write!(f, "CheckedUnderflow"),
            Error::CheckedOverflow(_) => write!(f, "CheckedOverflow"),
            Error::CheckedMul(_) => write!(f, "CheckedMul"),
            Error::CheckedDiv(_) => write!(f, "CheckedDiv"),
            Error::CheckedSub(_) => write!(f, "CheckedSub"),
            Error::CheckedAdd(_) => write!(f, "CheckedAdd"),
            Error::ERC20Failed(_) => write!(f, "ERC20Failed"),
        }
    }
}
