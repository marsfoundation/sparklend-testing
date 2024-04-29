// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import { console2 } from "forge-std/console2.sol";

import { IPool } from "sparklend-v1-core/contracts/interfaces/IPool.sol";   

import { UserActions } from "src/UserActions.sol";

contract HandlerBase is UserActions {

    uint256 constant MAX_TOKEN_AMOUNT = 1e30;

    address public pool;

    mapping(string => uint256) public data;  // Generic logging
    
    constructor(address pool_) {
        pool = pool_;
    }

    function _logAction(string memory key) internal {
        data[key]++;
    }

    function _getRandomReserve(uint256 assetIndex) internal view returns (address) {
        uint256 reserveLength = IPool(pool).getReservesCount();

        return IPool(pool).getReserveAddressById(uint16(_bound(assetIndex, 0, reserveLength - 1)));
    }

}
