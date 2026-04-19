// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "../../3_Vault.sol";

// TokenVault creates its own ClujUSD and is the sole manager.
// This helper exposes a mint function so tests can seed token balances.
contract MockVault is TokenVault {
    function mintTokensForTest(address _to, uint256 _amount) external {
        token.mint(_to, _amount);
    }
}
