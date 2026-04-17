// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "remix_tests.sol";
import "../4_FlashLoan.sol";

// A well-behaved borrower: records the callback and repays immediately
contract HonestBorrower {
    ClujUSD public token;
    bool public wasCalled;
    uint256 public receivedAmount;

    constructor(ClujUSD _token) {
        token = _token;
    }

    function onFlashLoan(uint256 _amount, bytes calldata) external {
        wasCalled      = true;
        receivedAmount = token.balanceOf(address(this));
        // Repay the vault
        token.transfer(msg.sender, _amount);
    }
}

// A dishonest borrower: never repays
contract DishonestBorrower {
    function onFlashLoan(uint256, bytes calldata) external pure {
        // does nothing — loan is not repaid
    }
}

contract FlashLoanTest {
    ClujUSD        cusd;
    TokenVault     vault;
    HonestBorrower honest;

    uint256 constant VAULT_LIQUIDITY = 100e18;
    uint256 constant LOAN_AMOUNT     = 50e18;

    function beforeEach() public {
        // Deploy a standalone ClujUSD where THIS contract is the manager
        cusd  = new ClujUSD();
        vault = new TokenVault(address(cusd));

        // Seed the vault with liquidity by minting directly to it
        cusd.mint(address(vault), VAULT_LIQUIDITY);

        honest = new HonestBorrower(cusd);
    }

    // --- flash loan is executed ---

    function testFlashLoanCallsOnFlashLoan() public {
        vault.flashLoan(address(honest), LOAN_AMOUNT, "");

        Assert.ok(
            honest.wasCalled(),
            "onFlashLoan must be called on the borrower"
        );
    }

    function testFlashLoanSendsTokensToBorrower() public {
        vault.flashLoan(address(honest), LOAN_AMOUNT, "");

        Assert.equal(
            honest.receivedAmount(),
            LOAN_AMOUNT,
            "borrower must receive exactly the requested loan amount"
        );
    }

    // --- vault is whole after repayment ---

    function testVaultBalanceRestoredAfterRepayment() public {
        vault.flashLoan(address(honest), LOAN_AMOUNT, "");

        Assert.equal(
            cusd.balanceOf(address(vault)),
            VAULT_LIQUIDITY,
            "vault balance must be fully restored after repayment"
        );
    }

    // --- reverts when loan is not repaid ---

    function testFlashLoanRevertsWhenNotRepaid() public {
        DishonestBorrower bad = new DishonestBorrower();
        bool reverted;

        try vault.flashLoan(address(bad), LOAN_AMOUNT, "") {
            reverted = false;
        } catch {
            reverted = true;
        }

        Assert.ok(reverted, "flashLoan must revert when the loan is not repaid");
    }

    // --- reverts when pool has insufficient liquidity ---

    function testFlashLoanRevertsOnInsufficientLiquidity() public {
        bool reverted;

        try vault.flashLoan(address(honest), VAULT_LIQUIDITY + 1, "") {
            reverted = false;
        } catch {
            reverted = true;
        }

        Assert.ok(reverted, "flashLoan must revert when amount exceeds pool liquidity");
    }
}
