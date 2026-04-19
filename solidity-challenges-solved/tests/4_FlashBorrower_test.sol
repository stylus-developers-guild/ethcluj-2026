// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "remix_tests.sol";
import "../4_FlashLoan.sol";
import "solidity-challenges-solved/tests/mock/MockOracle.sol";
import "solidity-challenges-solved/tests/mock/MockToken.sol";

// Students implement: FlashBorrower.onFlashLoan
// ─────────────────────────────────────────────────────────────────────────────
// Environment layout
// ──────────────────
//  MockOracle   : $2 000 / ETH (Chainlink 8-decimal format)
//  Manager      : WETH collateral → ClujUSD (CUSD) mint/burn
//  DEX pool     : 1 000 CUSD  +  1 WETH
//                 (WETH priced at 1 000 CUSD in the pool vs 2 000 at the oracle
//                  → price discrepancy that makes the flash-loan arbitrage viable)
//  TokenVault   : 500 CUSD seeded via depositTokens() — the proper LP path
//  FlashBorrower: borrow CUSD → swap for WETH → deposit as collateral →
//                 mint new CUSD → repay vault
//
// DEX liquidity source
// ────────────────────
//  CUSD : minted via Manager (2 WETH deposited → 1 500 CUSD minted;
//         1 000 go to the DEX, 500 go to the vault)
//  WETH : taken directly from the MockToken constructor pre-mint (10 000 WETH);
//         1 WETH is sent to the DEX without going through the Manager —
//         this is what creates the price gap that makes the arbitrage profitable.
//
// Math check (50 CUSD loan, amountIn = 50 CUSD swapped):
//   WETH out    = 50 * 1 / (1 000 + 50)  ≈ 0.04762 WETH
//   collat $    = 0.04762 * $2 000       ≈ $95.24
//   collatRatio = $95.24 / 50 CUSD      ≈ 1.905e18  ≥  1.5e18 ✓
// ─────────────────────────────────────────────────────────────────────────────
contract FlashBorrowerTest {
    MockToken     weth;
    Manager       manager;
    DEX           dex;
    TokenVault    vault;
    FlashBorrower flashBorrower;

    // DEX pool: WETH is "cheap" relative to oracle → arbitrage is profitable
    uint256 constant DEX_CUSD  = 1_000e18;
    uint256 constant DEX_WETH  = 1e18;

    // Vault seeded via depositTokens (the correct LP path, not direct mint)
    uint256 constant VAULT_CUSD = 500e18;

    // Flash loan parameters
    uint256 constant LOAN_AMOUNT = 50e18; // 50 CUSD borrowed from vault

    function beforeEach() public {
        // ── 1. Infrastructure ───────────────────────────────────────────────
        // MockToken constructor pre-mints 10 000 WETH to this contract.
        weth    = new MockToken("Wrapped Ethereum", "Weth");
        manager = new Manager(address(weth), address(new MockOracle()));

        // ── 2. Obtain CUSD through the Manager ───────────────────────────────
        // collatRatio = (2 WETH × $2 000) / 1 500 CUSD ≈ 2.67 ≥ 1.5 ✓
        weth.approve(address(manager), 2e18);
        manager.deposit(2e18);
        manager.mint(DEX_CUSD + VAULT_CUSD); // mint 1 500 CUSD

        // ── 3. Create DEX and seed it ────────────────────────────────────────
        // CUSD from Manager mint; WETH from pre-mint (bypasses Manager).
        // Pool ratio 1 WETH = 1 000 CUSD vs oracle 1 WETH = 2 000 CUSD → gap.
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

    // ── vault state ─────────────────────────────────────────────────────────

    function testRealFlashLoanRestoresVaultBalance() public {
        uint256 vaultBalBefore = manager.CUSD().balanceOf(address(vault));
        vault.flashLoan(address(flashBorrower), LOAN_AMOUNT, abi.encode(LOAN_AMOUNT));
        Assert.equal(manager.CUSD().balanceOf(address(vault)), vaultBalBefore,
            "vault CUSD balance must be fully restored after the flash loan");
    }

    function testVaultTotalSharesUnchangedAfterLoan() public {
        uint256 sharesBefore = vault.totalShares();
        vault.flashLoan(address(flashBorrower), LOAN_AMOUNT, abi.encode(LOAN_AMOUNT));
        Assert.equal(vault.totalShares(), sharesBefore,
            "vault totalShares must not change during a flash loan");
    }

    // ── FlashBorrower's Manager position ───────────────────────────────────

    function testRealFlashLoanDepositsWethInManager() public {
        vault.flashLoan(address(flashBorrower), LOAN_AMOUNT, abi.encode(LOAN_AMOUNT));
        Assert.greaterThan(manager.depositAmountOf(address(flashBorrower)), uint256(0),
            "FlashBorrower must have WETH deposited in the Manager after the flash loan");
    }

    function testRealFlashLoanCreatesMintedPosition() public {
        vault.flashLoan(address(flashBorrower), LOAN_AMOUNT, abi.encode(LOAN_AMOUNT));
        Assert.equal(manager.mintedAmountOf(address(flashBorrower)), LOAN_AMOUNT,
            "FlashBorrower must have minted exactly LOAN_AMOUNT CUSD via the Manager");
    }

    function testRealFlashLoanCollateralRatioIsSafe() public {
        vault.flashLoan(address(flashBorrower), LOAN_AMOUNT, abi.encode(LOAN_AMOUNT));
        Assert.greaterThan(
            manager.collatRatio(address(flashBorrower)),
            manager.MIN_COLLAT_RATIO(),
            "FlashBorrower collateral ratio must exceed the minimum after the flash loan"
        );
    }

    // ── FlashBorrower's token balances after the loan ───────────────────────

    function testFlashBorrowerHasZeroCUSDAfterLoan() public {
        vault.flashLoan(address(flashBorrower), LOAN_AMOUNT, abi.encode(LOAN_AMOUNT));
        Assert.equal(manager.CUSD().balanceOf(address(flashBorrower)), 0,
            "FlashBorrower must hold zero CUSD after repaying the vault");
    }

    function testFlashBorrowerHasZeroWETHAfterLoan() public {
        vault.flashLoan(address(flashBorrower), LOAN_AMOUNT, abi.encode(LOAN_AMOUNT));
        Assert.equal(weth.balanceOf(address(flashBorrower)), 0,
            "FlashBorrower must hold zero WETH after depositing it all into the Manager");
    }

    // ── DEX state after the swap ─────────────────────────────────────────────

    function testDexCUSDReserveIncreasedByLoanAmount() public {
        uint256 reserve1Before = dex.reserve1();
        vault.flashLoan(address(flashBorrower), LOAN_AMOUNT, abi.encode(LOAN_AMOUNT));
        Assert.equal(dex.reserve1(), reserve1Before + LOAN_AMOUNT,
            "DEX CUSD reserve must increase by the amount swapped by FlashBorrower");
    }

    function testDexWETHReserveDecreasedAfterSwap() public {
        uint256 reserve2Before = dex.reserve2();
        vault.flashLoan(address(flashBorrower), LOAN_AMOUNT, abi.encode(LOAN_AMOUNT));
        Assert.lesserThan(dex.reserve2(), reserve2Before,
            "DEX WETH reserve must decrease after FlashBorrower swaps CUSD for WETH");
    }

    function testDexWETHReserveDecreasedByExactSwapAmount() public {
        // amountOut = LOAN_AMOUNT * DEX_WETH / (DEX_CUSD + LOAN_AMOUNT)
        uint256 expectedWethOut = LOAN_AMOUNT * DEX_WETH / (DEX_CUSD + LOAN_AMOUNT);
        vault.flashLoan(address(flashBorrower), LOAN_AMOUNT, abi.encode(LOAN_AMOUNT));
        Assert.equal(dex.reserve2(), DEX_WETH - expectedWethOut,
            "DEX WETH reserve must decrease by the exact constant-product amountOut");
    }
}
