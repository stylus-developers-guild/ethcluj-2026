// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "remix_tests.sol";
import "solidity-challenges/tests/mock/MockVault.sol";

// Students implement: mintShares, burnShares, withdrawTokens
contract VaultTest {
    MockVault vault;

    uint256 constant DEPOSIT = 100e18;

    function beforeEach() public {
        vault = new MockVault();

        // Give this test contract tokens and approve the vault
        vault.mintTokensForTest(address(this), 200e18);
        vault.token().approve(address(vault), 200e18);
    }

    // ── mintShares (exercised via depositTokens) ────────────────────────────

    function testDepositMintsShares() public {
        vault.depositTokens(DEPOSIT);
        Assert.greaterThan(vault.sharesOf(address(this)), uint256(0),
            "shares must be minted after deposit");
    }

    function testDepositIncreasesTotalShares() public {
        vault.depositTokens(DEPOSIT);
        Assert.greaterThan(vault.totalShares(), uint256(0),
            "totalShares must increase after deposit");
    }

    function testFirstDepositorSharesEqualDepositAmount() public {
        vault.depositTokens(DEPOSIT);
        Assert.equal(vault.sharesOf(address(this)), DEPOSIT,
            "first depositor shares must equal deposited amount");
    }

    function testTwoEqualDepositsDoubleSharesAndTotal() public {
        vault.depositTokens(DEPOSIT);
        vault.depositTokens(DEPOSIT);
        Assert.equal(vault.sharesOf(address(this)), DEPOSIT * 2,
            "two equal deposits must double the user's shares");
        Assert.equal(vault.totalShares(), DEPOSIT * 2,
            "totalShares must equal the sum of all shares minted");
    }

    // ── burnShares (exercised via withdrawTokens) ───────────────────────────

    function testWithdrawReturnsTokensToUser() public {
        vault.depositTokens(DEPOSIT);
        uint256 balanceBefore = vault.token().balanceOf(address(this));
        uint256 shares = vault.sharesOf(address(this));
        vault.withdrawTokens(shares);
        Assert.greaterThan(vault.token().balanceOf(address(this)), balanceBefore,
            "user must receive tokens back after withdrawal");
    }

    function testWithdrawReturnsExactDepositedAmount() public {
        vault.depositTokens(DEPOSIT);
        uint256 shares = vault.sharesOf(address(this));
        vault.withdrawTokens(shares);
        // Started with 200e18, deposited 100e18, got 100e18 back → 200e18
        Assert.equal(vault.token().balanceOf(address(this)), 200e18,
            "user must get back exactly the deposited amount");
    }

    function testPartialWithdrawReturnsProportionalTokens() public {
        vault.depositTokens(DEPOSIT);
        uint256 shares = vault.sharesOf(address(this));
        // Withdraw half the shares → should get back half the deposit
        vault.withdrawTokens(shares / 2);
        // Had 200e18, deposited 100e18 → 100e18 in hand; got back 50e18 → 150e18
        Assert.equal(vault.token().balanceOf(address(this)), 150e18,
            "partial withdrawal must return tokens proportional to shares burned");
    }

    function testWithdrawEmptiesVaultTokenBalance() public {
        vault.depositTokens(DEPOSIT);
        uint256 shares = vault.sharesOf(address(this));
        vault.withdrawTokens(shares);
        Assert.equal(vault.token().balanceOf(address(vault)), uint256(0),
            "vault token balance must be zero after the sole depositor withdraws fully");
    }
}
