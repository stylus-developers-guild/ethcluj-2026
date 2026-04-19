// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// A well-behaved borrower: records that the callback fired and repays immediately.
// Used to verify the vault's flash-loan *mechanics* independently of any strategy.
contract HonestBorrower {
    ERC20 public token;
    bool public wasCalled;
    uint256 public receivedAmount;

    constructor(ERC20 _token) {
        token = _token;
    }

    function onFlashLoan(uint256 _amount, bytes calldata) external {
        wasCalled = true;
        receivedAmount = token.balanceOf(address(this));
        token.transfer(msg.sender, _amount);
    }
}

// A dishonest borrower that never repays — the vault must revert.
contract DishonestBorrower {
    function onFlashLoan(uint256, bytes calldata) external pure {}
}