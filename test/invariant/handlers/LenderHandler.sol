// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import { IAToken } from "sparklend-v1-core/contracts/interfaces/IAToken.sol";
import { IPool }   from "sparklend-v1-core/contracts/interfaces/IPool.sol";   

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

    function supplyAndUseAsCollateral(uint256 userIndex, uint256 assetIndex, uint256 amount) public {
        address user = lenders[_bound(userIndex, 0, lenders.length - 1)];

        amount = _bound(amount, 1, MAX_TOKEN_AMOUNT);

        _supplyAndUseAsCollateral(pool, user, _getRandomReserve(assetIndex), amount);

        _logAction("supplyAndUseAsCollateral");
    }

    function withdraw(uint256 userIndex, uint256 assetIndex, uint256 amount) public {
        address user    = lenders[_bound(userIndex, 0, lenders.length - 1)];
        address reserve = _getRandomReserve(assetIndex);

        IAToken aToken = IAToken(IPool(pool).getReserveData(reserve).aTokenAddress);

        uint256 balance = aToken.balanceOf(user);

        if (balance == 0) {
            _logAction("withdraw - early exit");
            return;
        }

        amount = _bound(amount, 1, balance);

        _withdraw(pool, user, _getRandomReserve(assetIndex), amount);

        _logAction("withdraw");
    }

}
