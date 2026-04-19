// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

// Returns $2000 per ETH with 8 decimals (Chainlink format)
contract MockOracle {
    function latestAnswer() external pure returns (uint256) {
        return 2000e8;
    }
}
