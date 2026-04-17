// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "remix_tests.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../1_Dex.sol";

contract MockToken is ERC20 {
    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {}

    function mint(address _to, uint256 _amount) external {
        _mint(_to, _amount);
    }
}

contract DexTest {
    MockToken token1;
    MockToken token2;
    DEX dex;

    // Redeploy fresh state before every test so tests are independent
    function beforeEach() public {
        token1 = new MockToken("Token1", "TK1");
        token2 = new MockToken("Token2", "TK2");
        dex = new DEX(address(token1), address(token2));

        token1.mint(address(this), 200e18);
        token2.mint(address(this), 200e18);
        token1.approve(address(dex), 200e18);
        token2.approve(address(dex), 200e18);

        // Seed pool with 100 / 100 liquidity
        dex.addLiquidity(100e18, 100e18);
    }

    // --- swapToken1ForToken2 ---

    function testSwap1For2IncreasesReserve1() public {
        uint256 amountIn = 10e18;
        uint256 reserve1Before = dex.reserve1();

        token1.approve(address(dex), amountIn);
        dex.swapToken1ForToken2(amountIn);

        Assert.equal(
            dex.reserve1(),
            reserve1Before + amountIn,
            "reserve1 must increase by amountIn"
        );
    }

    function testSwap1For2DecreasesReserve2() public {
        uint256 amountIn = 10e18;
        uint256 reserve2Before = dex.reserve2();

        token1.approve(address(dex), amountIn);
        dex.swapToken1ForToken2(amountIn);

        Assert.lesserThan(
            dex.reserve2(),
            reserve2Before,
            "reserve2 must decrease after swap"
        );
    }

    function testSwap1For2TransfersToken2ToUser() public {
        uint256 amountIn = 10e18;
        uint256 balanceBefore = token2.balanceOf(address(this));

        token1.approve(address(dex), amountIn);
        dex.swapToken1ForToken2(amountIn);

        Assert.greaterThan(
            token2.balanceOf(address(this)),
            balanceBefore,
            "user must receive token2"
        );
    }

    function testSwap1For2TakesToken1FromUser() public {
        uint256 amountIn = 10e18;
        uint256 balanceBefore = token1.balanceOf(address(this));

        token1.approve(address(dex), amountIn);
        dex.swapToken1ForToken2(amountIn);

        Assert.equal(
            token1.balanceOf(address(this)),
            balanceBefore - amountIn,
            "amountIn of token1 must leave user wallet"
        );
    }

    // --- swapToken2ForToken1 ---

    function testSwap2For1IncreasesReserve2() public {
        uint256 amountIn = 10e18;
        uint256 reserve2Before = dex.reserve2();

        token2.approve(address(dex), amountIn);
        dex.swapToken2ForToken1(amountIn);

        Assert.equal(
            dex.reserve2(),
            reserve2Before + amountIn,
            "reserve2 must increase by amountIn"
        );
    }

    function testSwap2For1DecreasesReserve1() public {
        uint256 amountIn = 10e18;
        uint256 reserve1Before = dex.reserve1();

        token2.approve(address(dex), amountIn);
        dex.swapToken2ForToken1(amountIn);

        Assert.lesserThan(
            dex.reserve1(),
            reserve1Before,
            "reserve1 must decrease after swap"
        );
    }

    function testSwap2For1TransfersToken1ToUser() public {
        uint256 amountIn = 10e18;
        uint256 balanceBefore = token1.balanceOf(address(this));

        token2.approve(address(dex), amountIn);
        dex.swapToken2ForToken1(amountIn);

        Assert.greaterThan(
            token1.balanceOf(address(this)),
            balanceBefore,
            "user must receive token1"
        );
    }

    function testSwap2For1TakesToken2FromUser() public {
        uint256 amountIn = 10e18;
        uint256 balanceBefore = token2.balanceOf(address(this));

        token2.approve(address(dex), amountIn);
        dex.swapToken2ForToken1(amountIn);

        Assert.equal(
            token2.balanceOf(address(this)),
            balanceBefore - amountIn,
            "amountIn of token2 must leave user wallet"
        );
    }
}
