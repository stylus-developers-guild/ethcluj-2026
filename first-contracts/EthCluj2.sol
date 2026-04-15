// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

contract EthCluj {

    struct Info {
        uint256 favoriteNumber;
        string name;
    }

    mapping(address who  => Info info) public favoriteNumberOf;

    event FavoriteNumberChanged(string who, uint256 newFavoriteNumber);
	
    constructor (string memory _myName, uint256 _myFavoriteNumber) {
        changeFavoriteNumber(_myName, _myFavoriteNumber);
    }

    function changeFavoriteNumber(string memory _who, uint256 _newFavoriteNumber) public {
        // Map a new instance of the info struct to the address of the caller
        favoriteNumberOf[msg.sender] = Info(_newFavoriteNumber, _who);
        // We emit the envent with relevant fields
        emit FavoriteNumberChanged(_who, _newFavoriteNumber);
    }
}
