// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { UserConfiguration } from "aave-v3-core/contracts/protocol/libraries/configuration/UserConfiguration.sol";
import { Errors }            from "aave-v3-core/contracts/protocol/libraries/helpers/Errors.sol";
import { DataTypes }         from "aave-v3-core/contracts/protocol/libraries/types/DataTypes.sol";

import { IERC20, SparkLendTestBase } from "./SparkLendTestBase.sol";

contract LiquidationCallTestBase is SparkLendTestBase {

    address borrower   = makeAddr("borrower");
    address lender     = makeAddr("lender");
    address liquidator = makeAddr("liquidator");

    function test_liquidationCall_whenCollateralAssetNotActive() public {
        vm.prank(admin);
        poolConfigurator.setReserveActive(address(collateralAsset), false);

        vm.expectRevert(bytes(Errors.RESERVE_INACTIVE));
        pool.liquidationCall(address(collateralAsset), address(borrowAsset), borrower, 1e18, false);
    }

    function test_liquidationCall_whenBorrowAssetNotActive() public {
        vm.prank(admin);
        poolConfigurator.setReserveActive(address(borrowAsset), false);

        vm.expectRevert(bytes(Errors.RESERVE_INACTIVE));
        pool.liquidationCall(address(collateralAsset), address(borrowAsset), borrower, 1e18, false);
    }

    function test_liquidationCall_whenCollateralAssetPaused() public {
        vm.prank(admin);
        poolConfigurator.setReservePause(address(collateralAsset), true);

        vm.expectRevert(bytes(Errors.RESERVE_PAUSED));
        pool.liquidationCall(address(collateralAsset), address(borrowAsset), borrower, 1e18, false);
    }

    function test_liquidationCall_whenBorrowAssetPaused() public {
        vm.prank(admin);
        poolConfigurator.setReservePause(address(borrowAsset), true);

        vm.expectRevert(bytes(Errors.RESERVE_PAUSED));
        pool.liquidationCall(address(collateralAsset), address(borrowAsset), borrower, 1e18, false);
    }

    function test_liquidationCall_whenCollateralAssetFrozen_success() public {
        setUpLiquidatablePosition();

        vm.prank(admin);
        poolConfigurator.setReserveFreeze(address(collateralAsset), true);

        vm.startPrank(liquidator);
        borrowAsset.mint(liquidator, 500 ether);
        borrowAsset.approve(address(pool), 500 ether);

        pool.liquidationCall(address(collateralAsset), address(borrowAsset), borrower, 500 ether, false);
    }

    function test_liquidationCall_whenBorrowAssetFrozen_success() public {
        setUpLiquidatablePosition();

        vm.prank(admin);
        poolConfigurator.setReserveFreeze(address(borrowAsset), true);

        vm.startPrank(liquidator);
        borrowAsset.mint(liquidator, 500 ether);
        borrowAsset.approve(address(pool), 500 ether);

        pool.liquidationCall(address(collateralAsset), address(borrowAsset), borrower, 500 ether, false);
    }

    function setUpLiquidatablePosition() internal {
        _initCollateral({
            asset:                address(collateralAsset),
            ltv:                  50_00,
            liquidationThreshold: 50_00,
            liquidationBonus:     100_01
        });

        vm.prank(admin);
        poolConfigurator.setReserveBorrowing(address(borrowAsset), true);

        _supply(lender, address(borrowAsset), 500 ether);

        _supplyAndUseAsCollateral(borrower, address(collateralAsset), 1000 ether);

        _borrow(borrower, address(borrowAsset), 500 ether);

        vm.warp(365 days);
    }


}
