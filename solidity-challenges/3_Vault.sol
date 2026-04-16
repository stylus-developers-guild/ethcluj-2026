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


// For this challenge, we will implement our own token vault
// Users will be able to lend out their money to a trusted smart contract
contract TokenVault {
    ClujUSD public token;
    uint256 public totalShares;
    mapping(address who => uint256 shares) public sharesOf;

    constructor() {
        token = new ClujUSD();
    }

    // ASSIGNMENT: implement mintSHares
    // It should:
    // 1. increment total shares by _amount
    // 2. increment sharesOf the _to address by _amount
    function mintShares(address _to, uint256 _amount) private {}

    // ASSIGNMENT: implement burnSHares
    // It should:
    // 1. decrement total shares by _amount
    // 2. decrement sharesOf the _from address by _amount
    function burnShares(address _from, uint256 _amount) private {}

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

    // ASSIGNMENT: implement the wthdrawTokens
    // It should:
    // 1. create the amount. this should be created by multiplying _shares by the token balance of 
    // this contract, then dividing this by the total amount of shares
    // 2. burn the shares
    // 3. transfer the amount to the sender
    function withdrawTokens(uint256 _shares) external {}
}


