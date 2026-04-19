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
contract ClujUSD is ERC20("ClujUSD", "cusd") {
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
    ClujUSD public cusd;

    IOracle public oracle;

    mapping(address user => uint256 amount) public depositAmountOf;
    mapping(address user => uint256 amount) public mintedAmountOf;

    constructor(address _weth, address _oracle) {
        // We deploy our instance of the token at the same time we are
        // deploying the manager
        cusd= new ClujUSD();
        weth = ERC20(_weth);
        oracle = IOracle(_oracle);
    }

    // ASSIGNMENT: implement the the deposit function
    // It should:
    // 1. Transfer _amount of weth from the users wallet into this  contract
    // 2. Add the _amount to the users depositAmountOf
    function deposit(uint256 _amount) external {
        weth.transferFrom(msg.sender, address(this), _amount);
        depositAmountOf[msg.sender] += _amount;
    }

    // ASSIGNMENT: implement the burn function
    // It should:
    // 1. Subtract _amount from the users mintedAmountOf
    // 2. Burn _amount of cusd from the users wallet
    function burn(uint256 _amount) external {
        mintedAmountOf[msg.sender] -= _amount;
        cusd.burn(msg.sender, _amount);
    }

    // ASSIGNMENT: implement the mint function
    // It should:
    // 1. Add _amount to the users mintedAmountOf
    // 2. Check that the users collateral ratio is >= MIN_COLLAT_RATIO
    // 3. Mint _amount of cusd to the user
    function mint(uint256 _amount) external {
        mintedAmountOf[msg.sender] += _amount;
        require(
            collatRatio(msg.sender) >= MIN_COLLAT_RATIO,
            "Collateral ratio is too low"
        );
        cusd.mint(msg.sender, _amount);
    }

    // ASSIGNMENT: implement the withdraw function
    // It should:
    // 1. Subtract _amount from the users depositAmountOf
    // 2. Check that the users collateral ratio is >= MIN_COLLAT_RATIO
    // 3. Transfer _amount of WETH to the user
    function withdraw(uint256 _amount) external  {
        depositAmountOf[msg.sender] -= _amount;
        require(
            collatRatio(msg.sender) >= MIN_COLLAT_RATIO,
            "Collateral ratio is too low"
        );
        weth.transfer(msg.sender, _amount);
    }

    function liquidate(address _user) external {
        require(collatRatio(_user) < MIN_COLLAT_RATIO);
        cusd.burn(msg.sender, mintedAmountOf[_user]);
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
        _res = (totalValue * 1e18) / minted;
    }
}
