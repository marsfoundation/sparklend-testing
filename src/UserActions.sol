// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IPool } from "aave-v3-core/contracts/interfaces/IPool.sol";

import { MockERC20 } from "erc20-helpers/MockERC20.sol";

import "forge-std/Test.sol";

// Contract of abstracted functions of user actions
contract UserActions is Test {

    function _useAsCollateral(address pool, address user, address newCollateralAsset) internal {
        vm.prank(user);
        IPool(pool).setUserUseReserveAsCollateral(newCollateralAsset, true);
    }

    function _borrow(address pool, address user, address asset, uint256 amount) internal {
        vm.prank(user);
        IPool(pool).borrow(asset, amount, 2, 0, user);
    }

    function _supply(address pool, address user, address asset, uint256 amount) internal {
        vm.startPrank(user);
        deal(asset, user, amount);
        // MockERC20(asset).mint(user, amount);
        MockERC20(asset).approve(address(pool), amount);
        IPool(pool).supply(asset, amount, user, 0);
        vm.stopPrank();
    }

    function _repay(address pool, address user, address asset, uint256 amount) internal {
        vm.startPrank(user);
        MockERC20(asset).approve(address(pool), amount);
        IPool(pool).repay(asset, amount, 2, user);
        vm.stopPrank();
    }

    function _withdraw(address pool, address user, address asset, uint256 amount) internal {
        vm.prank(user);
        IPool(pool).withdraw(asset, amount, user);
    }

    function _supplyAndUseAsCollateral(address pool, address user, address asset, uint256 amount)
        internal
    {
        _supply(pool, user, asset, amount);
        _useAsCollateral(pool, user, asset);
    }

}
