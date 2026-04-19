// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "remix_tests.sol";
import "../4_FlashLoan.sol";
import "solidity-challenges-solved/tests/mock/MockBorrower.sol";

// Students implement: TokenVault.flashLoan
// ─────────────────────────────────────────────────────────────────────────────
// Setup: standalone ClujUSD where this contract is the manager (direct mint),
// so we can seed the vault without going through Manager.
// ─────────────────────────────────────────────────────────────────────────────
contract FlashLoanTest {
    ClujUSD        cusd;
    TokenVault     vault;
    HonestBorrower honest;

    uint256 constant VAULT_LIQUIDITY = 100e18;
    uint256 constant LOAN_AMOUNT     = 50e18;

    function beforeEach() public {
        cusd  = new ClujUSD();
        vault = new TokenVault(address(cusd));
        cusd.mint(address(vault), VAULT_LIQUIDITY);
        honest = new HonestBorrower(cusd);
    }

    // ── callback mechanics ──────────────────────────────────────────────────

    function testFlashLoanCallsOnFlashLoan() public {
        vault.flashLoan(address(honest), LOAN_AMOUNT, "");
        Assert.ok(honest.wasCalled(),
            "onFlashLoan must be called on the borrower");
    }

    function testFlashLoanSendsExactAmountToBorrower() public {
        vault.flashLoan(address(honest), LOAN_AMOUNT, "");
        Assert.equal(honest.receivedAmount(), LOAN_AMOUNT,
            "borrower must receive exactly the requested loan amount inside the callback");
    }

    // ── revert cases ────────────────────────────────────────────────────────

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
