// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "remix_tests.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../2_StableCoin.sol";

contract MockWETH is ERC20 {
    constructor() ERC20("Wrapped Ether", "WETH") {}
    function mint(address _to, uint256 _amount) external { _mint(_to, _amount); }
}

// Returns $2000 per ETH with 8 decimals (Chainlink format)
contract MockOracle {
    function latestAnswer() external pure returns (uint256) {
        return 2000e8;
    }
}

// Minimal DEX that accepts two ERC-20 tokens and provides addLiquidity.
// Used to verify that CUSD minted from WETH can seed a real liquidity pool.
// No-arg constructor: Remix test runner tries to deploy every contract it sees;
// setup() separates token assignment so the runner can instantiate this safely.
contract MockDEX {
    ERC20 public token1; // CUSD
    ERC20 public token2; // WETH
    uint256 public reserve1;
    uint256 public reserve2;

    function setup(address _cusd, address _weth) external {
        token1 = ERC20(_cusd);
        token2 = ERC20(_weth);
    }

    function addLiquidity(uint256 _amount1, uint256 _amount2) external {
        token1.transferFrom(msg.sender, address(this), _amount1);
        token2.transferFrom(msg.sender, address(this), _amount2);
        reserve1 += _amount1;
        reserve2 += _amount2;
    }
}

contract StableCoinTest {
    MockWETH weth;
    Manager  manager;
    MockDEX  dex;

    // 1 ETH deposited, oracle says $2000 → totalValue = $2000
    // Minting 1000 CUSD → collatRatio = 2.0 (above the 1.5 minimum)
    uint256 constant DEPOSIT_AMOUNT = 1e18;
    uint256 constant MINT_AMOUNT    = 1000e18;

    function beforeEach() public {
        weth    = new MockWETH();
        manager = new Manager(address(weth), address(new MockOracle()));
        dex     = new MockDEX(address(manager.CUSD()), address(weth));

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

    // --- full cycle: WETH → CUSD → DEX liquidity pool ---

    // Demonstrates the end-to-end flow:
    //   1. Deposit WETH as collateral
    //   2. Mint CUSD against that collateral
    //   3. Seed a DEX pool with the freshly minted CUSD + WETH
    //
    // Pool: 1000 CUSD + 0.5 WETH reflects approximately half the oracle price
    // (1 WETH = 2000 CUSD at oracle, pool ratio 1 WETH = 2000 CUSD here too).
    function testMintedCUSDCanSeedDexLiquidityPool() public {
        uint256 poolCUSD = MINT_AMOUNT;   // 1000 CUSD
        uint256 poolWETH = DEPOSIT_AMOUNT / 2; // 0.5 WETH

        // Deposit 1 WETH → collatRatio = ($2000) / 1000 CUSD = 2.0 ≥ 1.5
        manager.deposit(DEPOSIT_AMOUNT);
        manager.mint(MINT_AMOUNT);

        // Approve DEX to pull CUSD (just minted) and WETH from this contract
        manager.CUSD().approve(address(dex), poolCUSD);
        weth.approve(address(dex), poolWETH);

        dex.addLiquidity(poolCUSD, poolWETH);

        Assert.equal(
            dex.reserve1(),
            poolCUSD,
            "DEX must hold the CUSD minted from WETH collateral"
        );
        Assert.equal(
            dex.reserve2(),
            poolWETH,
            "DEX must hold the WETH used to pair with CUSD"
        );
    }
}
