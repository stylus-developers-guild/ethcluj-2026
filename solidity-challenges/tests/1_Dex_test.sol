// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "remix_tests.sol";
import "../1_Dex.sol";
import "solidity-challenges/tests/mock/MockToken.sol";

// Students implement: swapToken1ForToken2 and swapToken2ForToken1
// (token transfers, reserve updates, Swap event)
contract DexTest {
    MockToken cusd; // token1: stablecoin
    MockToken weth; // token2: collateral token
    DEX dex;

    // Pool seeded at oracle price: 2000 CUSD per 1 WETH
    uint256 constant POOL_CUSD = 2000e18;
    uint256 constant POOL_WETH = 1e18;

    // Swap amounts kept small to limit slippage
    uint256 constant SWAP_CUSD = 10e18;
    uint256 constant SWAP_WETH = 1e16; // 0.01 WETH

    function beforeEach() public {
        cusd = new MockToken("ClujUSD", "CUSD");
        weth = new MockToken("Wrapped Ethereum", "WETH");
        dex = new DEX(address(cusd), address(weth));

        cusd.approve(address(dex), POOL_CUSD + SWAP_CUSD);
        weth.approve(address(dex), POOL_WETH + SWAP_WETH);

        // Seed pool at oracle price
        dex.addLiquidity(POOL_CUSD, POOL_WETH);
    }

    // ── swapToken1ForToken2 (CUSD → WETH) ──────────────────────────────────

    function testSwap1For2IncreasesReserve1ByExactAmountIn() public {
        dex.swapToken1ForToken2(SWAP_CUSD);
        Assert.equal(dex.reserve1(), POOL_CUSD + SWAP_CUSD,
            "reserve1 must increase by exactly amountIn");
    }

    function testSwap1For2DecreasesReserve2() public {
        uint256 r2Before = dex.reserve2();
        dex.swapToken1ForToken2(SWAP_CUSD);
        Assert.lesserThan(dex.reserve2(), r2Before,
            "reserve2 must decrease after swap");
    }

    function testSwap1For2SetsReserve2ByConstantProductFormula() public {
        uint256 expectedOut = SWAP_CUSD * POOL_WETH / (POOL_CUSD + SWAP_CUSD);
        dex.swapToken1ForToken2(SWAP_CUSD);
        Assert.equal(dex.reserve2(), POOL_WETH - expectedOut,
            "reserve2 must decrease by the constant-product amountOut");
    }

    function testSwap1For2TakesExactAmountInFromUser() public {
        uint256 cusdBefore = cusd.balanceOf(address(this));
        dex.swapToken1ForToken2(SWAP_CUSD);
        Assert.equal(cusd.balanceOf(address(this)), cusdBefore - SWAP_CUSD,
            "user must lose exactly amountIn of CUSD");
    }

    function testSwap1For2SendsToken2ToUser() public {
        uint256 wethBefore = weth.balanceOf(address(this));
        dex.swapToken1ForToken2(SWAP_CUSD);
        Assert.greaterThan(weth.balanceOf(address(this)), wethBefore,
            "user must receive WETH after swap");
    }

    function testSwap1For2SendsExactAmountOutToUser() public {
        uint256 expectedOut = SWAP_CUSD * POOL_WETH / (POOL_CUSD + SWAP_CUSD);
        uint256 wethBefore = weth.balanceOf(address(this));
        dex.swapToken1ForToken2(SWAP_CUSD);
        Assert.equal(weth.balanceOf(address(this)), wethBefore + expectedOut,
            "user must receive the exact constant-product amountOut");
    }

    // ── swapToken2ForToken1 (WETH → CUSD) ──────────────────────────────────

    function testSwap2For1IncreasesReserve2ByExactAmountIn() public {
        dex.swapToken2ForToken1(SWAP_WETH);
        Assert.equal(dex.reserve2(), POOL_WETH + SWAP_WETH,
            "reserve2 must increase by exactly amountIn");
    }

    function testSwap2For1DecreasesReserve1() public {
        uint256 r1Before = dex.reserve1();
        dex.swapToken2ForToken1(SWAP_WETH);
        Assert.lesserThan(dex.reserve1(), r1Before,
            "reserve1 must decrease after swap");
    }

    function testSwap2For1SetsReserve1ByConstantProductFormula() public {
        uint256 expectedOut = SWAP_WETH * POOL_CUSD / (POOL_WETH + SWAP_WETH);
        dex.swapToken2ForToken1(SWAP_WETH);
        Assert.equal(dex.reserve1(), POOL_CUSD - expectedOut,
            "reserve1 must decrease by the constant-product amountOut");
    }

    function testSwap2For1TakesExactAmountInFromUser() public {
        uint256 wethBefore = weth.balanceOf(address(this));
        dex.swapToken2ForToken1(SWAP_WETH);
        Assert.equal(weth.balanceOf(address(this)), wethBefore - SWAP_WETH,
            "user must lose exactly amountIn of WETH");
    }

    function testSwap2For1SendsToken1ToUser() public {
        uint256 cusdBefore = cusd.balanceOf(address(this));
        dex.swapToken2ForToken1(SWAP_WETH);
        Assert.greaterThan(cusd.balanceOf(address(this)), cusdBefore,
            "user must receive CUSD after swap");
    }

    function testSwap2For1SendsExactAmountOutToUser() public {
        uint256 expectedOut = SWAP_WETH * POOL_CUSD / (POOL_WETH + SWAP_WETH);
        uint256 cusdBefore = cusd.balanceOf(address(this));
        dex.swapToken2ForToken1(SWAP_WETH);
        Assert.equal(cusd.balanceOf(address(this)), cusdBefore + expectedOut,
            "user must receive the exact constant-product amountOut");
    }
}
