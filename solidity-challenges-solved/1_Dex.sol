// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

// We create an interface to be able to interact with the transderFrom and transfer functions that
// all erc20 tokens have.
//
// Think of this as something we can put on top of an address, and therefore assume that the contract
// deployed at this address has these following 2 functions
// If it has, we will pass the function call safely to that contract
// If not, we are in quite a pickle...
// Luckely we know all erc20 tokens must comply with the spec, and therefore they must include some certain
// functions
interface IERC20 {
    function transferFrom(address _sender, address _recipient, uint256 _amount) external returns (bool);
    function transfer(address _recipient, uint256 _amount) external;
}

contract DEX {
    // State variables
    // An interface can serve as a type too
    IERC20 public token1;
    IERC20 public token2;
    uint256 public reserve1;
    uint256 public reserve2;
    uint256 public totalSupply;
    mapping(address LP => uint256 LPTokens) public balanceOf;

    // Events
    // ASSIGNMENT: create an event for when a swap happened
    // Make sure it displays the sender and the amount in and out
    event Swap(address sender, uint256 amountIn, uint256 amountOut);
    event AddLiquidity(address sender, uint256 amount1, uint256 amount2);
    event RemoveLiquidity(address sender, uint256 amount1, uint256 amount2);

    // We are sending in the addresses of the erc20 tokens to the constructor...
    constructor(address _token1, address _token2) {
        // ...and casting them to the IERC20 interface
        token1 = IERC20(_token1);
        token2 = IERC20(_token2);
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

        // ASSIGNMENT:
        // 1. send the _amountIn of token1 from our users wallet to this contract
        // 2. then send amountOut of token2 to the users wallet
        token1.transferFrom(msg.sender, address(this), _amountIn);
        token2.transfer(msg.sender, amountOut);

        // ASSIGNMENT:
        // 1. increment the reserve1 by _amountIn
        // 2. decrement the reserve2 by amountOut
        reserve1 += _amountIn;
        reserve2 -= amountOut;

        // ASSIGNMENT: Use our event for swaps and emit it here
        emit Swap(msg.sender, _amountIn, amountOut);
    }

    // Swap token2 for token1
    function swapToken2ForToken1(uint256 _amountIn) external {
        require(_amountIn > 0, "Amount must be greater than 0");

        // Calculate amount out using constant product formula
        uint256 amountOut = (_amountIn * reserve1) / (reserve2 + _amountIn);
        require(amountOut > 0, "Insufficient output amount");

        // ASSIGNMENT:
        // 1. send the _amountIn of token2 from our users wallet to this contract
        // 2. then send amountOut of token1 to the users wallet
        token2.transferFrom(msg.sender, address(this), _amountIn);
        token1.transfer(msg.sender, amountOut);

        // ASSIGNMENT:
        // 1. increment the reserve2 by _amountIn
        // 2. decrement the reserve1 by amountOut
        reserve2 += _amountIn;
        reserve1 -= amountOut;

        // ASSIGNMENT: Use our event for swaps and emit it here
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

    function min(uint256 _value1, uint256 _value2) private pure returns (uint256 _res) {
        _res = _value1 < _value2 ? _value1 : _value2;
    }
}
