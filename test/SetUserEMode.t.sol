// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { UserConfiguration } from "sparklend-v1-core/contracts/protocol/libraries/configuration/UserConfiguration.sol";
import { Errors }            from "sparklend-v1-core/contracts/protocol/libraries/helpers/Errors.sol";
import { DataTypes }         from "sparklend-v1-core/contracts/protocol/libraries/types/DataTypes.sol";

import { IERC20, SparkLendTestBase } from "./SparkLendTestBase.sol";

contract SetUserEModeTestBase is SparkLendTestBase {

    address borrower = makeAddr("borrower");

    function setUp() public virtual override {
        super.setUp();

        _initCollateral({
            asset:                address(collateralAsset),
            ltv:                  50_00,
            liquidationThreshold: 50_00,
            liquidationBonus:     100_01
        });

        vm.startPrank(admin);

        poolConfigurator.setReserveBorrowing(address(borrowAsset),     true);
        poolConfigurator.setReserveBorrowing(address(collateralAsset), true);

        poolConfigurator.setEModeCategory({
            categoryId:           1,
            ltv:                  60_00,
            liquidationThreshold: 60_00,
            liquidationBonus:     105_00,
            oracle:               address(0),
            label:                "emode1"
        });
        poolConfigurator.setEModeCategory({
            categoryId:           2,
            ltv:                  70_00,
            liquidationThreshold: 70_00,
            liquidationBonus:     105_00,
            oracle:               address(0),
            label:                "emode2"
        });

        poolConfigurator.setAssetEModeCategory(address(collateralAsset), 1);
        poolConfigurator.setAssetEModeCategory(address(borrowAsset),     2);

        vm.stopPrank();

        _supplyAndUseAsCollateral(borrower, address(collateralAsset), 1000 ether);
    }

}

contract SetUserEModeFailureTests is SetUserEModeTestBase {

    function test_setUserEMode_liquidationThresholdIsZero() public {
        vm.expectRevert(bytes(Errors.INCONSISTENT_EMODE_CATEGORY));
        pool.setUserEMode(3);
    }

    function test_setUserEMode_userHasOtherEModeWithActiveBorrow() public {
        vm.prank(borrower);
        pool.setUserEMode(1);

        _borrow(borrower, address(collateralAsset), 100 ether);

        vm.prank(borrower);
        vm.expectRevert(bytes(Errors.INCONSISTENT_EMODE_CATEGORY));
        pool.setUserEMode(2);
    }

    function test_setUserEMode_userExitsEModeAndGoesBelowHFBoundary() public {
        vm.prank(borrower);
        pool.setUserEMode(1);

        _borrow(borrower, address(collateralAsset), 500 ether);  // Right at 50% LT

        ( ,,,,, uint256 healthFactor ) = pool.getUserAccountData(borrower);

        assertEq(healthFactor, 1.2e18); 
        
        uint256 snapshot = vm.snapshot();

        vm.prank(borrower);
        pool.setUserEMode(0);

        ( ,,,,, healthFactor ) = pool.getUserAccountData(borrower);

        assertEq(healthFactor, 1e18);  // Perfectly at 1.0 since no time has passed

        vm.revertTo(snapshot);

        skip(1 seconds);

        vm.prank(borrower);
        vm.expectRevert(bytes(Errors.HEALTH_FACTOR_LOWER_THAN_LIQUIDATION_THRESHOLD));
        pool.setUserEMode(0);
    }

}
