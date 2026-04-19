// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "remix_tests.sol";
import "../4_FlashLoan.sol";
import "solidity-challenges/tests/mock/MockOracle.sol";
import "solidity-challenges/tests/mock/MockToken.sol";
import "solidity-challenges/tests/mock/MockBorrower.sol";


// ─────────────────────────────────────────────────────────────────────────────
// Test suite 1 — TokenVault flash-loan mechanics (isolated from any strategy)
// ─────────────────────────────────────────────────────────────────────────────
contract FlashLoanTest {
    ClujUSD cusd;
    TokenVault vault;
    HonestBorrower honest;

    uint256 constant VAULT_LIQUIDITY = 100e18;
    uint256 constant LOAN_AMOUNT = 50e18;

    function beforeEach() public {
        // Deploy a standalone ClujUSD where THIS contract is the manager,
        // so we can mint directly to seed the vault without going through Manager.
        cusd = new ClujUSD();
        vault = new TokenVault(address(cusd));

        cusd.mint(address(vault), VAULT_LIQUIDITY);

        honest = new HonestBorrower(cusd);
    }

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

    function testVaultBalanceRestoredAfterRepayment() public {
        vault.flashLoan(address(honest), LOAN_AMOUNT, "");

        Assert.equal(
            cusd.balanceOf(address(vault)),
            VAULT_LIQUIDITY,
            "vault balance must be fully restored after repayment"
        );
    }

    function testFlashLoanRevertsWhenNotRepaid() public {
        DishonestBorrower bad = new DishonestBorrower();
        bool reverted;

        try vault.flashLoan(address(bad), LOAN_AMOUNT, "") {
            reverted = false;
        } catch {
            reverted = true;
        }
        Assert.ok(
            reverted,
            "flashLoan must revert when the loan is not repaid"
        );
    }

    function testFlashLoanRevertsOnInsufficientLiquidity() public {
        bool reverted;

        try vault.flashLoan(address(honest), VAULT_LIQUIDITY + 1, "") {
            reverted = false;
        } catch {
            reverted = true;
        }
        Assert.ok(
            reverted,
            "flashLoan must revert when amount exceeds pool liquidity"
        );
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Test suite 2 — Real FlashBorrower arbitrage through a full DeFi environment
//
// Environment layout
// ──────────────────
//  MockOracle  : $2 000 / ETH (Chainlink 8-decimal format)
//  Manager     : WETH collateral → ClujUSD (CUSD) mint/burn
//  DEX pool    : 1 000 CUSD  +  1 WETH
//                (WETH priced at 1 000 CUSD in the pool vs 2 000 at the oracle
//                 → price discrepancy that makes the flash-loan arbitrage viable)
//  TokenVault  : 500 CUSD seeded via depositTokens() — the proper LP path
//  FlashBorrower: borrow CUSD → swap for WETH → deposit as collateral →
//                 mint new CUSD → repay vault
//
// Math check (50 CUSD loan, amountIn = 50 CUSD swapped):
//   WETH out  = 50 * 1 / (1000 + 50)  ≈ 0.04762 WETH
//   collat $  = 0.04762 * $2000       ≈ $95.24
//   collatRatio = $95.24 / 50 CUSD   ≈ 1.905  ≥ 1.5 ✓
// ─────────────────────────────────────────────────────────────────────────────
contract FlashBorrowerTest {
    MockToken weth;
    Manager manager;
    DEX dex;
    TokenVault vault;
    FlashBorrower flashBorrower;

    // DEX pool: WETH is "cheap" relative to oracle → arbitrage is profitable
    uint256 constant DEX_CUSD = 1_000e18;
    uint256 constant DEX_WETH = 1e18;

    // Vault seeded via depositTokens (the correct LP path, not direct mint)
    uint256 constant VAULT_CUSD = 500e18;

    // Flash loan parameters
    uint256 constant LOAN_AMOUNT = 50e18; // 50 CUSD borrowed from vault

    function beforeEach() public {
        // ── 1. Infrastructure ───────────────────────────────────────────────
        weth = new MockToken("Wrapped Ethereum", "Weth");
        manager = new Manager(address(weth), address(new MockOracle()));

        // ── 2. Mint WETH and obtain CUSD through the Manager ─────────────────
        // We need DEX_CUSD + VAULT_CUSD = 1500 CUSD total.
        // collatRatio = (depositWETH * $2000) / 1500 CUSD >= 1.5
        //   → depositWETH >= 1.125 WETH  →  use 2 WETH for a safe buffer
        weth.approve(address(manager), 2e18);
        manager.deposit(2e18);
        manager.mint(DEX_CUSD + VAULT_CUSD); // mint 1500 CUSD

        // ── 3. Create DEX and seed it with CUSD + WETH ───────────────────────
        // token1 = CUSD, token2 = WETH (matches FlashBorrower.swapToken1ForToken2)
        dex = new DEX(address(manager.CUSD()), address(weth));

        manager.CUSD().approve(address(dex), DEX_CUSD);
        weth.approve(address(dex), DEX_WETH);
        dex.addLiquidity(DEX_CUSD, DEX_WETH);

        // ── 4. Create vault and seed it with CUSD via depositTokens ──────────
        vault = new TokenVault(address(manager.CUSD()));

        manager.CUSD().approve(address(vault), VAULT_CUSD);
        vault.depositTokens(VAULT_CUSD);

        // ── 5. Deploy the real FlashBorrower ─────────────────────────────────
        flashBorrower = new FlashBorrower(
            ERC20(address(manager.CUSD())),
            dex,
            manager
        );
    }

    // After a full flash loan the vault must end up with exactly as many CUSD
    // as it started with (the vault is whole — borrower repaid).
    function testRealFlashLoanRestoresVaultBalance() public {
        uint256 vaultBalanceBefore = manager.CUSD().balanceOf(address(vault));

        // _data encodes how much CUSD the FlashBorrower should swap for WETH
        vault.flashLoan(
            address(flashBorrower),
            LOAN_AMOUNT,
            abi.encode(LOAN_AMOUNT)
        );

        Assert.equal(
            manager.CUSD().balanceOf(address(vault)),
            vaultBalanceBefore,
            "vault CUSD balance must be fully restored after the real flash loan"
        );
    }

    // The FlashBorrower should have deposited WETH collateral into the Manager.
    function testRealFlashLoanDepositsWethInManager() public {
        vault.flashLoan(
            address(flashBorrower),
            LOAN_AMOUNT,
            abi.encode(LOAN_AMOUNT)
        );

        Assert.greaterThan(
            manager.depositAmountOf(address(flashBorrower)),
            uint256(0),
            "FlashBorrower must have WETH deposited in the Manager after the flash loan"
        );
    }

    // The FlashBorrower must have a minted CUSD position equal to the loan amount.
    function testRealFlashLoanCreatesMintedPosition() public {
        vault.flashLoan(
            address(flashBorrower),
            LOAN_AMOUNT,
            abi.encode(LOAN_AMOUNT)
        );

        Assert.equal(
            manager.mintedAmountOf(address(flashBorrower)),
            LOAN_AMOUNT,
            "FlashBorrower must have minted exactly LOAN_AMOUNT CUSD via the Manager"
        );
    }

    // The collateral ratio for the FlashBorrower must stay above the minimum —
    // this proves the position is healthy and not immediately liquidatable.
    function testRealFlashLoanCollateralRatioIsSafe() public {
        vault.flashLoan(
            address(flashBorrower),
            LOAN_AMOUNT,
            abi.encode(LOAN_AMOUNT)
        );

        Assert.greaterThan(
            manager.collatRatio(address(flashBorrower)),
            manager.MIN_COLLAT_RATIO(),
            "FlashBorrower collateral ratio must exceed the minimum after the flash loan"
        );
    }
}
