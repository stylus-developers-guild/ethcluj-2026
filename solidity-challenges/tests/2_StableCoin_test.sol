// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "remix_tests.sol";
import "../2_StableCoin.sol";
import "solidity-challenges/tests/mock/MockToken.sol";
import "solidity-challenges/tests/mock/MockOracle.sol";

// Students implement: deposit, mint, burn, withdraw
//
// Constants:
//   1 WETH deposited, oracle $2 000 → totalValue = $2 000
//   Minting 1 000 CUSD → collatRatio = 2.0e18  (above 1.5e18 minimum)
contract StableCoinTest {
    MockToken weth;
    Manager   manager;

    uint256 constant DEPOSIT_AMOUNT = 1e18;    // 1 WETH
    uint256 constant MINT_AMOUNT    = 1000e18; // 1 000 CUSD

    function beforeEach() public {
        weth    = new MockToken("Wrapped Ethereum", "Weth");
        manager = new Manager(address(weth), address(new MockOracle()));
        weth.approve(address(manager), 10e18);
    }

    // ── deposit ────────────────────────────────────────────────────────────

    function testDepositIncreasesDepositAmountOf() public {
        manager.deposit(DEPOSIT_AMOUNT);
        Assert.equal(manager.depositAmountOf(address(this)), DEPOSIT_AMOUNT,
            "depositAmountOf must equal deposited amount");
    }

    function testDepositTransfersWethToManager() public {
        uint256 managerBalBefore = weth.balanceOf(address(manager));
        manager.deposit(DEPOSIT_AMOUNT);
        Assert.equal(weth.balanceOf(address(manager)), managerBalBefore + DEPOSIT_AMOUNT,
            "manager must hold the deposited WETH");
    }

    function testDepositDecreasesUserWethBalance() public {
        uint256 userBalBefore = weth.balanceOf(address(this));
        manager.deposit(DEPOSIT_AMOUNT);
        Assert.equal(weth.balanceOf(address(this)), userBalBefore - DEPOSIT_AMOUNT,
            "user WETH balance must decrease by the deposited amount");
    }

    function testMultipleDepositsAccumulate() public {
        manager.deposit(DEPOSIT_AMOUNT);
        manager.deposit(DEPOSIT_AMOUNT);
        Assert.equal(manager.depositAmountOf(address(this)), DEPOSIT_AMOUNT * 2,
            "repeated deposits must accumulate in depositAmountOf");
    }

    // ── mint ───────────────────────────────────────────────────────────────

    function testMintIncreasesMintedAmountOf() public {
        manager.deposit(DEPOSIT_AMOUNT);
        manager.mint(MINT_AMOUNT);
        Assert.equal(manager.mintedAmountOf(address(this)), MINT_AMOUNT,
            "mintedAmountOf must equal minted amount");
    }

    function testMintSendsCUSDToUser() public {
        manager.deposit(DEPOSIT_AMOUNT);
        manager.mint(MINT_AMOUNT);
        Assert.equal(manager.CUSD().balanceOf(address(this)), MINT_AMOUNT,
            "user must receive CUSD after mint");
    }

    function testMintIncreasesCUSDTotalSupply() public {
        manager.deposit(DEPOSIT_AMOUNT);
        manager.mint(MINT_AMOUNT);
        Assert.equal(manager.CUSD().totalSupply(), MINT_AMOUNT,
            "CUSD total supply must increase by the minted amount");
    }

    function testCollatRatioIsCorrectAfterMint() public {
        // 1 WETH × $2 000 / 1 000 CUSD = ratio 2.0 → stored as 2e18
        manager.deposit(DEPOSIT_AMOUNT);
        manager.mint(MINT_AMOUNT);
        Assert.equal(manager.collatRatio(address(this)), 2e18,
            "collatRatio must be 2.0e18 with 1 WETH collateral and 1 000 CUSD minted");
    }

    function testMintRevertsWhenCollatRatioTooLow() public {
        // 1 WETH → max safe mint at 1.5× = $2000/1.5 ≈ 1333 CUSD; trying 1400 must revert
        manager.deposit(DEPOSIT_AMOUNT);
        bool reverted;
        try manager.mint(1400e18) { reverted = false; } catch { reverted = true; }
        Assert.ok(reverted, "mint must revert when collateral ratio would fall below minimum");
    }

    function testMintRevertsWithNoCollateral() public {
        bool reverted;
        try manager.mint(MINT_AMOUNT) { reverted = false; } catch { reverted = true; }
        Assert.ok(reverted, "mint must revert when there is no collateral deposited");
    }

    // ── burn ───────────────────────────────────────────────────────────────

    function testBurnDecreasesMintedAmountOf() public {
        manager.deposit(DEPOSIT_AMOUNT);
        manager.mint(MINT_AMOUNT);
        uint256 burnAmount = 400e18;
        manager.burn(burnAmount);
        Assert.equal(manager.mintedAmountOf(address(this)), MINT_AMOUNT - burnAmount,
            "mintedAmountOf must decrease by burned amount");
    }

    function testBurnRemovesCUSDFromUser() public {
        manager.deposit(DEPOSIT_AMOUNT);
        manager.mint(MINT_AMOUNT);
        uint256 burnAmount = 400e18;
        manager.burn(burnAmount);
        Assert.equal(manager.CUSD().balanceOf(address(this)), MINT_AMOUNT - burnAmount,
            "user CUSD balance must decrease after burn");
    }

    function testBurnReducesTotalSupply() public {
        manager.deposit(DEPOSIT_AMOUNT);
        manager.mint(MINT_AMOUNT);
        uint256 burnAmount = 400e18;
        uint256 supplyBefore = manager.CUSD().totalSupply();
        manager.burn(burnAmount);
        Assert.lesserThan(manager.CUSD().totalSupply(), supplyBefore,
            "CUSD total supply must decrease after burn");
    }

    // ── withdraw ───────────────────────────────────────────────────────────

    function testWithdrawDecreasesDepositAmountOf() public {
        manager.deposit(DEPOSIT_AMOUNT);
        uint256 withdrawAmount = 0.1e18;
        manager.withdraw(withdrawAmount);
        Assert.equal(manager.depositAmountOf(address(this)), DEPOSIT_AMOUNT - withdrawAmount,
            "depositAmountOf must decrease by withdrawn amount");
    }

    function testWithdrawSendsWethToUser() public {
        manager.deposit(DEPOSIT_AMOUNT);
        uint256 withdrawAmount = 0.1e18;
        uint256 balanceBefore = weth.balanceOf(address(this));
        manager.withdraw(withdrawAmount);
        Assert.equal(weth.balanceOf(address(this)), balanceBefore + withdrawAmount,
            "user must receive WETH after withdraw");
    }

    function testWithdrawDecreasesManagerWethBalance() public {
        manager.deposit(DEPOSIT_AMOUNT);
        uint256 withdrawAmount = 0.1e18;
        uint256 managerBalBefore = weth.balanceOf(address(manager));
        manager.withdraw(withdrawAmount);
        Assert.lesserThan(weth.balanceOf(address(manager)), managerBalBefore,
            "manager WETH balance must decrease after withdraw");
    }

    function testWithdrawRevertsWhenItWouldUndercollateralise() public {
        // 1 WETH / 1 000 CUSD → ratio 2.0. Withdrawing 0.26 WETH leaves 0.74 WETH
        // → ratio = 0.74 × $2 000 / 1 000 = 1.48 < 1.5 → must revert
        manager.deposit(DEPOSIT_AMOUNT);
        manager.mint(MINT_AMOUNT);
        bool reverted;
        try manager.withdraw(0.26e18) { reverted = false; } catch { reverted = true; }
        Assert.ok(reverted, "withdraw that drops collateral ratio below minimum must revert");
    }

    // ── full cycle ─────────────────────────────────────────────────────────

    function testFullCycleDepositMintBurnWithdraw() public {
        manager.deposit(DEPOSIT_AMOUNT);
        manager.mint(MINT_AMOUNT);
        manager.burn(MINT_AMOUNT);

        uint256 wethBefore = weth.balanceOf(address(this));
        manager.withdraw(DEPOSIT_AMOUNT);

        Assert.equal(weth.balanceOf(address(this)), wethBefore + DEPOSIT_AMOUNT,
            "full cycle must return all WETH to user");
        Assert.equal(manager.depositAmountOf(address(this)), 0,
            "depositAmountOf must be zero after full withdrawal");
        Assert.equal(manager.mintedAmountOf(address(this)), 0,
            "mintedAmountOf must be zero after full burn");
        Assert.equal(manager.CUSD().totalSupply(), 0,
            "CUSD total supply must be zero after full burn");
    }
}
