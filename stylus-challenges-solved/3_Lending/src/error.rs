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
