// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

contract MockOracleSentinel {

    function isBorrowAllowed() external pure returns (bool) {
        return false;
    }

    function isLiquidationAllowed() external pure returns (bool) {
        return false;
    }

}
