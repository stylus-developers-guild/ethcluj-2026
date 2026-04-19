// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "remix_tests.sol";
import "solidity-challenges/tests/mock/MockVault.sol";

contract VaultTest {
    MockVault vault;

    uint256 constant DEPOSIT = 100e18;

    function beforeEach() public {
        vault = new MockVault();

        // Give this test contract some tokens and approve the vault
        vault.mintTokensForTest(address(this), 200e18);
        vault.token().approve(address(vault), 200e18);
    }

    // --- mintShares (tested via depositTokens) ---

    function testDepositMintsShares() public {
        vault.depositTokens(DEPOSIT);

        Assert.greaterThan(
            vault.sharesOf(address(this)),
            uint256(0),
            "shares must be minted after deposit"
        );
    }

    function testDepositUpdatesTotalShares() public {
        vault.depositTokens(DEPOSIT);

        Assert.greaterThan(
            vault.totalShares(),
            uint256(0),
            "totalShares must increase after deposit"
        );
    }

    function testDepositSharesEqualAmountOnFirstDeposit() public {
        vault.depositTokens(DEPOSIT);

        Assert.equal(
            vault.sharesOf(address(this)),
            DEPOSIT,
            "first depositor shares must equal deposited amount"
        );
    }

    // --- burnShares + withdrawTokens ---

    function testWithdrawBurnsShares() public {
        vault.depositTokens(DEPOSIT);
        uint256 shares = vault.sharesOf(address(this));

        vault.withdrawTokens(shares);

        Assert.equal(
            vault.sharesOf(address(this)),
            uint256(0),
            "shares must be zero after full withdrawal"
        );
    }

    function testWithdrawDecreasesTotalShares() public {
        vault.depositTokens(DEPOSIT);
        uint256 shares = vault.sharesOf(address(this));

        vault.withdrawTokens(shares);

        Assert.equal(
            vault.totalShares(),
            uint256(0),
            "totalShares must be zero after full withdrawal"
        );
    }

    function testWithdrawReturnsTokensToUser() public {
        vault.depositTokens(DEPOSIT);
        uint256 balanceBefore = vault.token().balanceOf(address(this));
        uint256 shares = vault.sharesOf(address(this));

        vault.withdrawTokens(shares);

        Assert.greaterThan(
            vault.token().balanceOf(address(this)),
            balanceBefore,
            "user must receive tokens back after withdrawal"
        );
    }

    function testWithdrawReturnsCorrectAmount() public {
        vault.depositTokens(DEPOSIT);
        uint256 shares = vault.sharesOf(address(this));

        vault.withdrawTokens(shares);

        // After a full withdraw with no yield, user should get back exactly what they put in
        Assert.equal(
            vault.token().balanceOf(address(this)),
            200e18, // started with 200e18, deposited 100e18, got 100e18 back
            "user must get back the exact deposited amount"
        );
    }
}
