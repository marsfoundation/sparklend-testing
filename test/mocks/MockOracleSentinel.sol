
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

contract MockOracleSentinel {

    function isBorrowAllowed() external pure returns (bool) {
        return false;
    }

}
