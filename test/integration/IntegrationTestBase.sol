// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { IPool } from "aave-v3-core/contracts/interfaces/IPool.sol";

import "sparklend-address-registry/Ethereum.sol";

import { UserActions } from "src/UserActions.sol";

contract IntegrationTestBase is UserActions {

    IPool constant pool = IPool(Ethereum.POOL);

    function setUp() public {
        vm.createSelectFork(getChain("mainnet").rpcUrl, 19_483_900);  // March 21, 2023
    }

    /**********************************************************************************************/
    /*** User helper functions                                                                  ***/
    /**********************************************************************************************/

    function _useAsCollateral(address user, address newCollateralAsset) internal {
        _useAsCollateral(address(pool), user, newCollateralAsset);
    }

    function _borrow(address user, address asset, uint256 amount) internal {
        _borrow(address(pool), user, asset, amount);
    }

    function _supply(address user, address asset, uint256 amount) internal {
        _supply(address(pool), user, asset, amount);
    }

    function _repay(address user, address asset, uint256 amount) internal {
        _repay(address(pool), user, asset, amount);
    }

    function _withdraw(address user, address asset, uint256 amount) internal {
        _withdraw(address(pool), user, asset, amount);
    }

    function _supplyAndUseAsCollateral(address user, address asset, uint256 amount) internal {
        _supplyAndUseAsCollateral(address(pool), user, asset, amount);
    }

}

