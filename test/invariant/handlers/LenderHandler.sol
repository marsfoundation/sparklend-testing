// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import { HandlerBase } from "test/invariant/handlers/HandlerBase.sol";

contract LenderHandler is HandlerBase {

    address[] public lenders;

    constructor(address pool_, uint256 numLenders) HandlerBase(pool_) {
        for(uint256 i = 0; i < numLenders; i++) {
            lenders.push(makeAddr(string(abi.encodePacked("lender", i))));
        }
    }

    function supply(uint256 userIndex, uint256 assetIndex, uint256 amount) public {
        address user = lenders[_bound(userIndex, 0, lenders.length - 1)];

        amount = _bound(amount, 1, MAX_TOKEN_AMOUNT);

        _supply(pool, user, _getRandomReserve(assetIndex), amount);

        _logAction("supply");
    }

}
