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
    }

}

// TODO: Use `proveNoOp` wherever applicable

contract SetUserEModeFailureTests is SetUserEModeTestBase {

    function test_setUserEMode_liquidationThresholdIsZero() public {
        vm.expectRevert(bytes(Errors.INCONSISTENT_EMODE_CATEGORY));
        pool.setUserEMode(3);
    }

    function test_setUserEMode_userHasOtherEModeWithActiveBorrow() public {
        vm.prank(borrower);
        pool.setUserEMode(1);

        _supplyAndUseAsCollateral(borrower, address(collateralAsset), 1000 ether);

        _borrow(borrower, address(collateralAsset), 100 ether);

        vm.prank(borrower);
        vm.expectRevert(bytes(Errors.INCONSISTENT_EMODE_CATEGORY));
        pool.setUserEMode(2);
    }

    function test_setUserEMode_userExitsEModeAndGoesBelowHFBoundary() public {
        vm.prank(borrower);
        pool.setUserEMode(1);

        _supplyAndUseAsCollateral(borrower, address(collateralAsset), 1000 ether);

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

contract SetUserEModeSuccessTests is SetUserEModeTestBase {

    modifier whenUserHasNotSuppliedAnyAssets { _; }

    modifier whenUserHasSuppliedAnAsset {
        _supply(borrower, address(collateralAsset), 1000 ether);
        _;
    }

    modifier whenUserDoesNotHaveActiveEMode { _; }

    modifier whenUserHasActiveEMode {
        vm.prank(borrower);
        pool.setUserEMode(1);

        assertEq(pool.getUserEMode(borrower), 1);

        _;
    }

    modifier whenUserHasAnActiveBorrow {
        vm.prank(borrower);
        pool.setUserUseReserveAsCollateral(address(collateralAsset), true);

        // NOTE: Borrow collateralAsset because its in same e-mode
        _borrow(borrower, address(collateralAsset), 100 ether);
        _;
    }

    modifier whenUserDoesNotHaveAnActiveBorrow { _; }

    function test_setUserEMode_01() 
        public 
        whenUserHasNotSuppliedAnyAssets 
        whenUserDoesNotHaveActiveEMode
    {
        vm.prank(borrower);
        pool.setUserEMode(0);

        assertEq(pool.getUserEMode(borrower), 0);
    }

    function test_setUserEMode_02() 
        public 
        whenUserHasNotSuppliedAnyAssets 
        whenUserDoesNotHaveActiveEMode
    {
        vm.prank(borrower);
        pool.setUserEMode(1);

        assertEq(pool.getUserEMode(borrower), 1);
    }

    function test_setUserEMode_03() 
        public 
        whenUserHasNotSuppliedAnyAssets 
        whenUserHasActiveEMode
    {
        vm.prank(borrower);
        pool.setUserEMode(0);

        assertEq(pool.getUserEMode(borrower), 0);
    }

    function test_setUserEMode_04() 
        public 
        whenUserHasNotSuppliedAnyAssets 
        whenUserHasActiveEMode
    {
        vm.prank(borrower);
        pool.setUserEMode(1);

        assertEq(pool.getUserEMode(borrower), 1);
    }

    function test_setUserEMode_05() 
        public 
        whenUserHasNotSuppliedAnyAssets 
        whenUserHasActiveEMode
    {
        vm.prank(borrower);
        pool.setUserEMode(2);

        assertEq(pool.getUserEMode(borrower), 2);
    }

    function test_setUserEMode_06() 
        public 
        whenUserHasSuppliedAnAsset
        whenUserDoesNotHaveActiveEMode
        whenUserDoesNotHaveAnActiveBorrow
    {
        vm.prank(borrower);
        pool.setUserEMode(0);

        assertEq(pool.getUserEMode(borrower), 0);
    }

    function test_setUserEMode_07() 
        public 
        whenUserHasSuppliedAnAsset
        whenUserDoesNotHaveActiveEMode
        whenUserDoesNotHaveAnActiveBorrow
    {
        vm.prank(borrower);
        pool.setUserEMode(1);

        assertEq(pool.getUserEMode(borrower), 1);
    }

    function test_setUserEMode_08() 
        public 
        whenUserHasSuppliedAnAsset
        whenUserDoesNotHaveActiveEMode
        whenUserHasAnActiveBorrow
    {
        vm.prank(borrower);
        pool.setUserEMode(0);

        assertEq(pool.getUserEMode(borrower), 0);
    }

    function test_setUserEMode_09() 
        public 
        whenUserHasSuppliedAnAsset
        whenUserDoesNotHaveActiveEMode
        whenUserHasAnActiveBorrow
    {
        vm.prank(borrower);
        pool.setUserEMode(1);

        assertEq(pool.getUserEMode(borrower), 1);
    }

    function test_setUserEMode_10() 
        public 
        whenUserHasSuppliedAnAsset
        whenUserHasActiveEMode
        whenUserDoesNotHaveAnActiveBorrow
    {
        vm.prank(borrower);
        pool.setUserEMode(0);

        assertEq(pool.getUserEMode(borrower), 0);
    }

    function test_setUserEMode_11() 
        public 
        whenUserHasSuppliedAnAsset
        whenUserHasActiveEMode
        whenUserDoesNotHaveAnActiveBorrow
    {
        vm.prank(borrower);
        pool.setUserEMode(1);

        assertEq(pool.getUserEMode(borrower), 1);
    }

    // Why is this possible? A user can change to an emode that doesn't match the asset
    // they have supplied. It only checks their active borrows. Can this be abused?
    function test_setUserEMode_INVESTIGATE() 
        public 
        whenUserHasSuppliedAnAsset
        whenUserHasActiveEMode
        whenUserDoesNotHaveAnActiveBorrow
    {
        vm.prank(borrower);
        pool.setUserEMode(2);

        assertEq(pool.getUserEMode(borrower), 2);
    }

    function test_setUserEMode_12() 
        public 
        whenUserHasSuppliedAnAsset
        whenUserHasActiveEMode
        whenUserHasAnActiveBorrow
    {
        vm.prank(borrower);
        pool.setUserEMode(0);

        assertEq(pool.getUserEMode(borrower), 0);
    }

    function test_setUserEMode_13() 
        public 
        whenUserHasSuppliedAnAsset
        whenUserHasActiveEMode
        whenUserHasAnActiveBorrow
    {
        vm.prank(borrower);
        pool.setUserEMode(1);

        assertEq(pool.getUserEMode(borrower), 1);
    }

}
