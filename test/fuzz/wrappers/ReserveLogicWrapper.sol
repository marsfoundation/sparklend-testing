// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import { ReserveLogic } from "aave-v3-core/contracts/protocol/libraries/logic/ReserveLogic.sol";
import { Pool }         from "aave-v3-core/contracts/protocol/pool/Pool.sol";

import {IPoolAddressesProvider} from 'aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol';

contract ReserveLogicWrapper is Pool {

    constructor(IPoolAddressesProvider provider) Pool(provider) {}

    function cumulateToLiquidityIndex(
        address reserve,
        uint256 totalLiquidity,
        uint256 amount
    ) external returns (uint256 updatedLiquidityIndex) {
        updatedLiquidityIndex
            = ReserveLogic.cumulateToLiquidityIndex(_reserves[reserve], totalLiquidity, amount);
    }
}
