// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "remix_tests.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../1_Dex.sol";

// Represents WETH — minted freely here to simulate a user who holds WETH
contract MockWETH is ERC20 {
    constructor() ERC20("Wrapped Ether", "WETH") {}
    function mint(address _to, uint256 _amount) external { _mint(_to, _amount); }
}

// Represents ClujUSD — in production this is minted by depositing WETH into the Manager.
// Here we mint it directly to simulate a user who has already gone through the Manager.
contract MockCUSD is ERC20 {
    constructor() ERC20("ClujUSD", "CUSD") {}
    function mint(address _to, uint256 _amount) external { _mint(_to, _amount); }
}

contract DexTest {
    MockCUSD cusd;  // token1: stablecoin (would normally be minted from WETH via Manager)
    MockWETH weth;  // token2: collateral token
    DEX dex;

    // Pool seeded at the oracle price: 2000 CUSD per 1 WETH ($2 000 / ETH).
    // This reflects the real relationship between CUSD and WETH.
    uint256 constant POOL_CUSD = 2000e18;
    uint256 constant POOL_WETH = 1e18;

    // Small swap amounts to keep slippage low.
    // Swapping CUSD in → WETH out: 10 CUSD trades for ~0.00497 WETH
    // Swapping WETH in → CUSD out: 0.01 WETH trades for ~19.8 CUSD
    uint256 constant SWAP_CUSD = 10e18;
    uint256 constant SWAP_WETH = 1e16; // 0.01 WETH

    function beforeEach() public {
        // Deploy the two tokens
        cusd = new MockCUSD();
        weth = new MockWETH();
        dex  = new DEX(address(cusd), address(weth));

        // Mint exactly what we need: pool amounts + one swap amount each
        cusd.mint(address(this), POOL_CUSD + SWAP_CUSD);   // 2010 CUSD
        weth.mint(address(this), POOL_WETH + SWAP_WETH);   // 1.01 WETH

        cusd.approve(address(dex), POOL_CUSD + SWAP_CUSD);
        weth.approve(address(dex), POOL_WETH + SWAP_WETH);

        // Seed pool at the oracle price so AMM starts fair
        dex.addLiquidity(POOL_CUSD, POOL_WETH);
    }

    // --- swapToken1ForToken2 (CUSD → WETH) ---

    function testSwap1For2IncreasesReserve1() public {
        uint256 reserve1Before = dex.reserve1();

        dex.swapToken1ForToken2(SWAP_CUSD);

        Assert.equal(
            dex.reserve1(),
            reserve1Before + SWAP_CUSD,
            "reserve1 must increase by amountIn"
        );
    }

    function testSwap1For2DecreasesReserve2() public {
        uint256 reserve2Before = dex.reserve2();

        dex.swapToken1ForToken2(SWAP_CUSD);

        Assert.lesserThan(
            dex.reserve2(),
            reserve2Before,
            "reserve2 must decrease after swap"
        );
    }

    function testSwap1For2TransfersToken2ToUser() public {
        uint256 balanceBefore = weth.balanceOf(address(this));

        dex.swapToken1ForToken2(SWAP_CUSD);

        Assert.greaterThan(
            weth.balanceOf(address(this)),
            balanceBefore,
            "user must receive WETH"
        );
    }

    function testSwap1For2TakesToken1FromUser() public {
        uint256 balanceBefore = cusd.balanceOf(address(this));

        dex.swapToken1ForToken2(SWAP_CUSD);

        Assert.equal(
            cusd.balanceOf(address(this)),
            balanceBefore - SWAP_CUSD,
            "amountIn of CUSD must leave user wallet"
        );
    }

    // --- swapToken2ForToken1 (WETH → CUSD) ---

    function testSwap2For1IncreasesReserve2() public {
        uint256 reserve2Before = dex.reserve2();

        dex.swapToken2ForToken1(SWAP_WETH);

        Assert.equal(
            dex.reserve2(),
            reserve2Before + SWAP_WETH,
            "reserve2 must increase by amountIn"
        );
    }

    function testSwap2For1DecreasesReserve1() public {
        uint256 reserve1Before = dex.reserve1();

        dex.swapToken2ForToken1(SWAP_WETH);

        Assert.lesserThan(
            dex.reserve1(),
            reserve1Before,
            "reserve1 must decrease after swap"
        );
    }

    function testSwap2For1TransfersToken1ToUser() public {
        uint256 balanceBefore = cusd.balanceOf(address(this));

        dex.swapToken2ForToken1(SWAP_WETH);

        Assert.greaterThan(
            cusd.balanceOf(address(this)),
            balanceBefore,
            "user must receive CUSD"
        );
    }

    function testSwap2For1TakesToken2FromUser() public {
        uint256 balanceBefore = weth.balanceOf(address(this));

        dex.swapToken2ForToken1(SWAP_WETH);

        Assert.equal(
            weth.balanceOf(address(this)),
            balanceBefore - SWAP_WETH,
            "amountIn of WETH must leave user wallet"
        );
    }
}
