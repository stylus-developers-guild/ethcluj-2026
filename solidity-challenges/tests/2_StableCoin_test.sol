// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "remix_tests.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../2_StableCoin.sol";

contract MockWETH is ERC20 {
    constructor() ERC20("MockWETH", "WETH") {}

    function mint(address _to, uint256 _amount) external {
        _mint(_to, _amount);
    }
}

// Returns $2000 per ETH with 8 decimals (Chainlink format)
contract MockOracle {
    function latestAnswer() external pure returns (uint256) {
        return 2000e8;
    }
}

contract StableCoinTest {
    MockWETH weth;
    Manager manager;

    // 1 ETH deposited, oracle says $2000 → totalValue = 2000e18
    // Minting 1000e18 CUSD gives collat ratio of 2.0 (above the 1.5 minimum)
    uint256 constant DEPOSIT_AMOUNT = 1e18;
    uint256 constant MINT_AMOUNT    = 1000e18;

    function beforeEach() public {
        weth    = new MockWETH();
        manager = new Manager(address(weth), address(new MockOracle()));

        weth.mint(address(this), 10e18);
        weth.approve(address(manager), 10e18);
    }

    // --- deposit ---

    function testDepositIncreasesDepositAmountOf() public {
        manager.deposit(DEPOSIT_AMOUNT);

        Assert.equal(
            manager.depositAmountOf(address(this)),
            DEPOSIT_AMOUNT,
            "depositAmountOf must equal deposited amount"
        );
    }

    function testDepositTransfersWethToContract() public {
        uint256 balanceBefore = weth.balanceOf(address(manager));
        manager.deposit(DEPOSIT_AMOUNT);

        Assert.equal(
            weth.balanceOf(address(manager)),
            balanceBefore + DEPOSIT_AMOUNT,
            "manager must hold the deposited WETH"
        );
    }

    // --- mint ---

    function testMintIncreasesMintedAmountOf() public {
        manager.deposit(DEPOSIT_AMOUNT);
        manager.mint(MINT_AMOUNT);

        Assert.equal(
            manager.mintedAmountOf(address(this)),
            MINT_AMOUNT,
            "mintedAmountOf must equal minted amount"
        );
    }

    function testMintSendsCUSDToUser() public {
        manager.deposit(DEPOSIT_AMOUNT);
        manager.mint(MINT_AMOUNT);

        Assert.equal(
            manager.CUSD().balanceOf(address(this)),
            MINT_AMOUNT,
            "user must receive CUSD after mint"
        );
    }

    // --- burn ---

    function testBurnDecreasesMinteAmountOf() public {
        manager.deposit(DEPOSIT_AMOUNT);
        manager.mint(MINT_AMOUNT);

        uint256 burnAmount = 400e18;
        manager.CUSD().approve(address(manager.CUSD()), burnAmount);
        manager.burn(burnAmount);

        Assert.equal(
            manager.mintedAmountOf(address(this)),
            MINT_AMOUNT - burnAmount,
            "mintedAmountOf must decrease by burned amount"
        );
    }

    function testBurnRemovesCUSDFromUser() public {
        manager.deposit(DEPOSIT_AMOUNT);
        manager.mint(MINT_AMOUNT);

        uint256 burnAmount = 400e18;
        manager.burn(burnAmount);

        Assert.equal(
            manager.CUSD().balanceOf(address(this)),
            MINT_AMOUNT - burnAmount,
            "user CUSD balance must decrease after burn"
        );
    }

    // --- withdraw ---

    function testWithdrawDecreasesDepositAmountOf() public {
        manager.deposit(DEPOSIT_AMOUNT);

        uint256 withdrawAmount = 0.1e18;
        manager.withdraw(withdrawAmount);

        Assert.equal(
            manager.depositAmountOf(address(this)),
            DEPOSIT_AMOUNT - withdrawAmount,
            "depositAmountOf must decrease by withdrawn amount"
        );
    }

    function testWithdrawSendsWethToUser() public {
        manager.deposit(DEPOSIT_AMOUNT);

        uint256 withdrawAmount = 0.1e18;
        uint256 balanceBefore = weth.balanceOf(address(this));
        manager.withdraw(withdrawAmount);

        Assert.equal(
            weth.balanceOf(address(this)),
            balanceBefore + withdrawAmount,
            "user must receive WETH after withdraw"
        );
    }
}
