// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { UserConfiguration } from "aave-v3-core/contracts/protocol/libraries/configuration/UserConfiguration.sol";
import { Errors }            from "aave-v3-core/contracts/protocol/libraries/helpers/Errors.sol";
import { DataTypes }         from "aave-v3-core/contracts/protocol/libraries/types/DataTypes.sol";

import { MockOracleSentinel } from "test/mocks/MockOracleSentinel.sol";

import { IERC20, SparkLendTestBase } from "./SparkLendTestBase.sol";

contract LiquidationCallTestBase is SparkLendTestBase {

    address borrower   = makeAddr("borrower");
    address lender     = makeAddr("lender");
    address liquidator = makeAddr("liquidator");

    function _setUpPosition(uint256 collateralAmount, uint256 borrowAmount) internal {
        _initCollateral({
            asset:                address(collateralAsset),
            ltv:                  50_00,
            liquidationThreshold: 50_00,
            liquidationBonus:     100_01
        });

        vm.prank(admin);
        poolConfigurator.setReserveBorrowing(address(borrowAsset), true);

        _supply(lender, address(borrowAsset), 500 ether);

        _supplyAndUseAsCollateral(borrower, address(collateralAsset), collateralAmount);

        _borrow(borrower, address(borrowAsset), borrowAmount);
    }

    function _setUpPosition() internal {
        _setUpPosition(1000 ether, 500 ether);
    }

    function _setUpLiquidatablePosition() internal {
        _setUpPosition();

        vm.warp(365 days);
    }

}

contract LiquidationCallFailureTest is LiquidationCallTestBase {

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
        _setUpLiquidatablePosition();

        vm.prank(admin);
        poolConfigurator.setReserveFreeze(address(collateralAsset), true);

        vm.startPrank(liquidator);
        borrowAsset.mint(liquidator, 500 ether);
        borrowAsset.approve(address(pool), 500 ether);

        pool.liquidationCall(address(collateralAsset), address(borrowAsset), borrower, 500 ether, false);
    }

    function test_liquidationCall_whenBorrowAssetFrozen_success() public {
        _setUpLiquidatablePosition();

        vm.prank(admin);
        poolConfigurator.setReserveFreeze(address(borrowAsset), true);

        vm.startPrank(liquidator);
        borrowAsset.mint(liquidator, 500 ether);
        borrowAsset.approve(address(pool), 500 ether);

        pool.liquidationCall(address(collateralAsset), address(borrowAsset), borrower, 500 ether, false);
    }

    function test_liquidationCall_priceSentinelActiveAndHealthFactorAboveThresholdAndLiquidationsNotAllowed() public {
        _setUpPosition();

        vm.warp(10 minutes);

        vm.startPrank(admin);
        poolAddressesProvider.setPriceOracleSentinel(address(new MockOracleSentinel()));
        vm.stopPrank();

        ( ,,,,, uint256 healthFactor ) = pool.getUserAccountData(borrower);

        // Less than MINIMUM_HEALTH_FACTOR_LIQUIDATION_THRESHOLD and below 1
        assertGt(healthFactor, 0.95e18);
        assertLt(healthFactor, 1e18);

        vm.expectRevert(bytes(Errors.PRICE_ORACLE_SENTINEL_CHECK_FAILED));
        pool.liquidationCall(address(collateralAsset), address(borrowAsset), borrower, 500 ether, false);
    }


    function test_liquidationCall_healthFactorGteOneBoundary() public {
        _setUpPosition();

        // Supply a large amount so less debt is owed to get closer to boundary
        _supply(lender, address(borrowAsset), 500_000_000 ether);

        vm.startPrank(liquidator);
        borrowAsset.mint(liquidator, 500 ether);
        borrowAsset.approve(address(pool), 500 ether);

        ( ,,,,, uint256 healthFactor ) = pool.getUserAccountData(borrower);

        assertEq(healthFactor, 1e18);

        vm.expectRevert(bytes(Errors.HEALTH_FACTOR_NOT_BELOW_THRESHOLD));
        pool.liquidationCall(address(collateralAsset), address(borrowAsset), borrower, 500 ether, false);

        vm.warp(block.timestamp + 1 seconds);

        ( ,,,,, healthFactor ) = pool.getUserAccountData(borrower);

        assertEq(healthFactor, 0.999999998420000002e18);  // Closest to 1e18 possible with config

        pool.liquidationCall(address(collateralAsset), address(borrowAsset), borrower, 500 ether, false);
    }

    // TODO: Don't think this code is reachable (isUsingAsCollateral == true while getLiquidationThreshold() != 0)
    //       because this code reverts on the _supplyAndUseAsCollateral with USER_IN_ISOLATION_MODE_OR_LTV_ZERO
    // function test_liquidationCall_liquidationThresholdZero() public {
    //     _initCollateral({
    //         asset:                address(collateralAsset),
    //         ltv:                  0,
    //         liquidationThreshold: 0,
    //         liquidationBonus:     0
    //     });

    //     vm.prank(admin);
    //     poolConfigurator.setReserveBorrowing(address(borrowAsset), true);

    //     _supply(lender, address(borrowAsset), 500 ether);

    //     _supplyAndUseAsCollateral(borrower, address(collateralAsset), 1000 ether);

    //     _borrow(borrower, address(borrowAsset), 500 ether);

    //     vm.expectRevert(bytes(Errors.COLLATERAL_CANNOT_BE_LIQUIDATED));
    //     pool.liquidationCall(address(borrowAsset), address(borrowAsset), borrower, 500 ether, false);
    // }

    function test_liquidationCall_notUsingAsCollateral() public {
        _setUpLiquidatablePosition();

        _initCollateral({
            asset:                address(borrowAsset),
            ltv:                  50_00,
            liquidationThreshold: 50_00,
            liquidationBonus:     100_01
        });

        vm.expectRevert(bytes(Errors.COLLATERAL_CANNOT_BE_LIQUIDATED));
        pool.liquidationCall(address(borrowAsset), address(borrowAsset), borrower, 500 ether, false);
    }

    function test_liquidationCall_userHasNoDebtOfDebtAsset() public {
        _setUpLiquidatablePosition();

        _initCollateral({
            asset:                address(borrowAsset),
            ltv:                  50_00,
            liquidationThreshold: 50_00,
            liquidationBonus:     100_01
        });

        vm.expectRevert(bytes(Errors.SPECIFIED_CURRENCY_NOT_BORROWED_BY_USER));
        pool.liquidationCall(address(collateralAsset), address(collateralAsset), borrower, 500 ether, false);
    }

    function test_liquidationCall_insufficientApproveBoundary() public {
        _setUpLiquidatablePosition();

        vm.startPrank(liquidator);
        borrowAsset.mint(liquidator, 500 ether);
        borrowAsset.approve(address(pool), 500 ether - 1);

        vm.expectRevert(stdError.arithmeticError);
        pool.liquidationCall(address(collateralAsset), address(borrowAsset), borrower, 500 ether, false);

        borrowAsset.approve(address(pool), 500 ether);

        pool.liquidationCall(address(collateralAsset), address(borrowAsset), borrower, 500 ether, false);
    }

    function test_liquidationCall_insufficientBalanceBoundary() public {
        _setUpLiquidatablePosition();

        vm.startPrank(liquidator);
        borrowAsset.mint(liquidator, 500 ether - 1);
        borrowAsset.approve(address(pool), 500 ether);

        vm.expectRevert(stdError.arithmeticError);
        pool.liquidationCall(address(collateralAsset), address(borrowAsset), borrower, 500 ether, false);

        borrowAsset.mint(liquidator, 1);

        pool.liquidationCall(address(collateralAsset), address(borrowAsset), borrower, 500 ether, false);
    }

}
