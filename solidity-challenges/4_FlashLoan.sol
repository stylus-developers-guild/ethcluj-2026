// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

// First we implement the OpenZeppelin implementation of the ERC20 token, in order to avoid
// having to reimplement it from scratch
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// After this we create an interface which is complient with oracles
interface IOracle {
    // This function will fetch the current price of WETH measured in USD
    function latestAnswer() external view returns (uint256 _res);
}

// This is the syntax for solidity inheritance.
// We are inheriting the ERC20 contract into our ClujUSD contract and then building on top of it
// This will also give it the transfer() and transferFrom() functions from the previous challange
// The paranthesis here is sending arguments to the ERC20 constructor:
//
// constructor(string memory name_, string memory symbol_)
//
// Feel free to press command + click / ctrl + click when you hover over the
// "ERC20" text on the line under this one in order to go to that file and inspect it
contract ClujUSD is ERC20("ClujUSD", "CUSD") {
    address public manager;

    constructor() {
        manager = msg.sender;
    }

    // This is a keyword called "modifier" in solidity
    // Think about it as a function that can execute stuff BEFORE or AFTER other functions
    modifier onlyManager() {
        // First we say what we want to execute
        require(manager == msg.sender);
        // Then in this line, the "_" is the placeholder for the actual function
        // if this line was before our "require(.." line, the function would execute before the actual
        // require check
        _;
    }

    // Now see how this is gatekeeping anyone but the address we assigned as
    // "manager" at the time of deplpoyment to interact with this function
    function mint(address _to, uint256 _amount) external onlyManager {
        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) external onlyManager {
        _burn(_from, _amount);
    }
}

contract Manager {
    uint public constant MIN_COLLAT_RATIO = 1.5e18;

    ERC20 public weth;
    ClujUSD public CUSD;

    IOracle public oracle;

    mapping(address user => uint256 amount) public depositAmountOf;
    mapping(address user => uint256 amount) public mintedAmountOf;

    constructor(address _weth, address _oracle) {
        // We deploy our instance of the token at the same time we are
        // deploying the manager
        CUSD = new ClujUSD();
        weth = ERC20(_weth);
        oracle = IOracle(_oracle);
    }

    function deposit(uint256 _amount) external {
        weth.transferFrom(msg.sender, address(this), _amount);
        depositAmountOf[msg.sender] += _amount;
    }

    function burn(uint256 _amount) external {
        mintedAmountOf[msg.sender] -= _amount;
        CUSD.burn(msg.sender, _amount);
    }

    function mint(uint256 _amount) external {
        mintedAmountOf[msg.sender] += _amount;
        require(
            collatRatio(msg.sender) >= MIN_COLLAT_RATIO,
            "Collateral ratio is too low"
        );
        CUSD.mint(msg.sender, _amount);
    }

    function withdraw(uint256 _amount) external {
        depositAmountOf[msg.sender] -= _amount;
        require(
            collatRatio(msg.sender) >= MIN_COLLAT_RATIO,
            "Collateral ratio is too low"
        );
        weth.transfer(msg.sender, _amount);
    }

    function liquidate(address _user) external {
        require(collatRatio(_user) < MIN_COLLAT_RATIO);
        CUSD.burn(msg.sender, mintedAmountOf[_user]);
        weth.transfer(msg.sender, depositAmountOf[_user]);
        depositAmountOf[_user] = 0;
        mintedAmountOf[_user] = 0;
    }

    function collatRatio(address _user) public view returns (uint256 _res) {
        uint256 minted = mintedAmountOf[_user];
        if (minted == 0) return type(uint256).max;
        // Function calls the oracle to get the current price of weth, using the
        // oracle.latestAnswer() function
        uint256 totalValue = (depositAmountOf[_user] *
            (oracle.latestAnswer() * 1e10)) / 1e18;
        _res = totalValue / minted;
    }
}

// For this challenge, we will implement our own token vault
// Users will be able to lend out their money to a trusted smart contract
contract TokenVault {
    ClujUSD public token;
    uint256 public totalShares;
    mapping(address who => uint256 shares) public sharesOf;

    constructor(address _token) {
        token = ClujUSD(_token);
    }

    function mintShares(address _to, uint256 _amount) private {
        totalShares += _amount;
        sharesOf[_to] += _amount;
    }

    function burnShares(address _from, uint256 _amount) private {
        totalShares -= _amount;
        sharesOf[_from] -= _amount;
    }

    function depositTokens(uint256 _amount) external {
        uint256 shares;
        if (totalShares == 0) {
            shares = _amount;
        } else {
            shares = (_amount * totalShares) / token.balanceOf(address(this));
        }

        mintShares(msg.sender, shares);
        token.transferFrom(msg.sender, address(this), _amount);
    }

    function withdrawTokens(uint256 _shares) external {
        uint256 amount = (_shares * token.balanceOf(address(this))) /
            totalShares;
        burnShares(msg.sender, _shares);
        token.transfer(msg.sender, amount);
    }

    // Now we added a flashloan function to this contract
    // Assignment: Implement the flashloan function
    // 1. Check if the pool has enough liquidity
    // 2. Transfer the amount to the borrower
    // 3. Call the onFlashLoan function of the borrower
    // 4. Check if the loan is repaid
    function flashLoan(
        address _borrower,
        uint256 _amount,
        bytes calldata _data
    ) external {}
}

contract FlashBorrower {
    ERC20 public token;
    DEX public dex;
    Manager public manager;

    constructor(ERC20 _token) {
        token = _token;
    }

    function onFlashLoan(uint256 _amount, bytes calldata _data) external {
        uint256 amountIn = abi.decode(_data, (uint256));
        // This is where the flash loan logic will take place
        // ASSIGNMENT:
        // Implement your own flashloan logic
        // It should:
        // 1. Swap ClujUSD for WETH in the dex
        // 2. Deposit the WETH in the manager
        // 3. Mint new ClujUSD
        //
        // The repayment we already have

        ERC20(token).transfer(msg.sender, _amount);
    }
}

contract DEX {
    // State variables
    // An interface can serve as a type too
    // ClujUSD
    ERC20 public token1;
    // Weth
    ERC20 public token2;
    uint256 public reserve1;
    uint256 public reserve2;
    uint256 public totalSupply;
    mapping(address LP => uint256 LPTokens) public balanceOf;

    event Swap(address sender, uint256 amountIn, uint256 amountOut);
    event AddLiquidity(address sender, uint256 amount1, uint256 amount2);
    event RemoveLiquidity(address sender, uint256 amount1, uint256 amount2);

    // We are sending in the addresses of the erc20 tokens to the constructor...
    constructor(address _token1, address _token2) {
        // ...and casting them to the IERC20 interface
        token1 = ERC20(_token1);
        token2 = ERC20(_token2);
    }

    // Add liquidity to the pool
    function addLiquidity(uint256 _amount1, uint256 _amount2) external {
        require(_amount1 > 0 && _amount2 > 0, "Amounts must be greater than 0");

        // This is how we use the interface, and interact with the erc20 functions
        // Note address(this) is solidity for: "Give me the address of this contract"
        token1.transferFrom(msg.sender, address(this), _amount1);
        // The transferFrom function is used when we want to move money from a
        // Wallet or contract that is NOT this contract
        // first argument is from where we are taking the money
        // second argument is to where we are sending the money
        // third argument is the amount
        token2.transferFrom(msg.sender, address(this), _amount2);

        // Calculate liquidity tokens to mint
        uint256 liquidity;
        if (totalSupply == 0) {
            liquidity = squareroot(_amount1 * _amount2);
        } else {
            liquidity = min(
                (_amount1 * totalSupply) / reserve1,
                (_amount2 * totalSupply) / reserve2
            );
        }

        // Update reserves and mint liquidity tokens
        // "+=" is syntactic sugar for incrementing values
        // Think of it as "i want to take the prior value of this variable
        // and add it with x"
        // This is the same as: reserve1 = reserve1 + _amount1
        // This also works with decrements "-="
        // That would be the same as: reserve1 = reserve1 - _amount1
        reserve1 += _amount1;
        reserve2 += _amount2;
        totalSupply += liquidity;
        balanceOf[msg.sender] += liquidity;

        emit AddLiquidity(msg.sender, _amount1, _amount2);
    }

    // Remove liquidity from the pool
    function removeLiquidity(uint256 _liquidity) external {
        require(_liquidity > 0, "Liquidity must be greater than 0");
        require(balanceOf[msg.sender] >= _liquidity, "Insufficient liquidity");

        // Calculate amounts to return
        uint256 amount1 = (_liquidity * reserve1) / totalSupply;
        uint256 amount2 = (_liquidity * reserve2) / totalSupply;

        // Update reserves and burn liquidity tokens
        reserve1 -= amount1;
        reserve2 -= amount2;
        totalSupply -= _liquidity;
        balanceOf[msg.sender] -= _liquidity;

        // Again, erc20 transactions from our interface
        token1.transfer(msg.sender, amount1);
        // The transfer function is for when we are sending money from THIS contract to somewhere else
        // First argument is to whom were sending money
        // Second argument is how much we are sending
        token2.transfer(msg.sender, amount2);

        emit RemoveLiquidity(msg.sender, amount1, amount2);
    }

    // Swap token1 for token2
    function swapToken1ForToken2(uint256 _amountIn) external {
        require(_amountIn > 0, "Amount must be greater than 0");

        // Calculate amount out using constant product formula
        uint256 amountOut = (_amountIn * reserve2) / (reserve1 + _amountIn);
        require(amountOut > 0, "Insufficient output amount");

        token1.transferFrom(msg.sender, address(this), _amountIn);
        token2.transfer(msg.sender, amountOut);

        reserve1 += _amountIn;
        reserve2 -= amountOut;

        emit Swap(msg.sender, _amountIn, amountOut);
    }

    // Swap token2 for token1
    function swapToken2ForToken1(uint256 _amountIn) external {
        require(_amountIn > 0, "Amount must be greater than 0");

        // Calculate amount out using constant product formula
        uint256 amountOut = (_amountIn * reserve1) / (reserve2 + _amountIn);
        require(amountOut > 0, "Insufficient output amount");

        token2.transferFrom(msg.sender, address(this), _amountIn);
        token1.transfer(msg.sender, amountOut);

        reserve2 += _amountIn;
        reserve1 -= amountOut;

        emit Swap(msg.sender, _amountIn, amountOut);
    }

    // Helper functions
    function squareroot(uint256 _input) private pure returns (uint256 _res) {
        if (_input > 3) {
            _res = _input;
            uint256 x = _input / 2 + 1;
            while (x < _res) {
                _res = x;
                x = (_input / x + x) / 2;
            }
        } else if (_input != 0) {
            _res = 1;
        }
    }

    function min(
        uint256 _value1,
        uint256 _value2
    ) private pure returns (uint256 _res) {
        _res = _value1 < _value2 ? _value1 : _value2;
    }
}
