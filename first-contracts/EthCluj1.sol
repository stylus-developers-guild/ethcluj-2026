// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

contract EthCluj {
    // Our initial starting number is 42, but this is subject to change
    uint256 public myFavoriteNumber = 42;

    function changeFavoriteNumber(uint256 _newFavoriteNumber) public {
        myFavoriteNumber = _newFavoriteNumber;
    }

    function timesTwo() public view returns (uint256 _res) {
        _res = myFavoriteNumber * 2;
    }

    function chain() external returns (uint256 _res) {
        // We call the changeFavoriteNumber function,
        // and pass in the result of timesTwo() this means
        // that myFavoriteNumber has gotten updated with this
        // new value
        changeFavoriteNumber(timesTwo());
        // Secontdly, we fetch our favorite number from storage
        // And assign it to the _res return argument
        _res = myFavoriteNumber;
    }
}
