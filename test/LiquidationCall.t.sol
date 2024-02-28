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
            liquidationBonus:     101_00
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

        skip(365 days);
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
            liquidationBonus:     101_00
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
            liquidationBonus:     101_00
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

contract LiquidationCallConcreteTest is LiquidationCallTestBase {

    address debtToken;

    function setUp() public override {
        super.setUp();

        debtToken = pool.getReserveData(address(borrowAsset)).variableDebtTokenAddress;
    }

    function test_liquidationCall_baseCase() public {
        _setUpLiquidatablePosition();

        vm.startPrank(liquidator);
        borrowAsset.mint(liquidator, 400 ether);
        borrowAsset.approve(address(pool), 400 ether);

        (
            AssertPoolReserveStateParams memory collateralReserveParams,
            AssertPoolReserveStateParams memory borrowReserveParams,
            AssertATokenStateParams      memory aCollateralAssetParams,
            AssertDebtTokenStateParams   memory borrowAssetDebtTokenParams,
            AssertAssetStateParams       memory collateralAssetParams,
            AssertAssetStateParams       memory borrowAssetParams,
            uint256 borrowerDebt,
            uint256 compoundedNormalizedInterest
        ) = _loadStartingParamsAndAssertState({
            timeSinceLastUpdate:         365 days,
            borrowerCollateral:          1000 ether,
            borrowerInitialBorrow:       500 ether,
            liquidatorLiquidationAmount: 400 ether
        });

        assertEq(borrowerDebt, 223.445957199470228858 ether);

        pool.liquidationCall(address(collateralAsset), address(borrowAsset), borrower, 400 ether, false);

        collateralReserveParams.lastUpdateTimestamp = 1 + 365 days;

        uint256 expectedLiquidityIndex      = 1e27 + (1e27 * 0.37e27 / 1e27);              // Normalized yield accrues full APR
        uint256 expectedVariableBorrowIndex = 1e27 * compoundedNormalizedInterest / 1e27;  // Accrues slightly more than APR

        assertEq(expectedLiquidityIndex,       1.37e27);
        assertEq(expectedVariableBorrowIndex,  1.446891914398940457716504e27);
        assertEq(compoundedNormalizedInterest, 1.446891914398940457716504e27);

        // Remaining debt for the user is the position minus the amount liquidated plus interest accrued
        uint256 remainingDebt = 500 ether + borrowerDebt - 400 ether;

        assertEq(remainingDebt, 323.445957199470228858 ether);

        // Remaining debt that the user owes divided by the current cash (liquidated amount) plus the outstanding debt
        ( uint256 borrowRate, uint256 liquidityRate ) = _getUpdatedRates(remainingDebt, 400 ether + remainingDebt);

        assertEq(borrowRate,    0.061177267423387126110513189e27);
        assertEq(liquidityRate, 0.027351787128930695623282914e27);

        borrowReserveParams.liquidityIndex            = expectedLiquidityIndex;
        borrowReserveParams.currentLiquidityRate      = liquidityRate + 1;  // Rounding
        borrowReserveParams.variableBorrowIndex       = expectedVariableBorrowIndex;
        borrowReserveParams.currentVariableBorrowRate = borrowRate;
        borrowReserveParams.lastUpdateTimestamp       = 1 + 365 days;

        aCollateralAssetParams.userBalance = 600 ether - 4 ether;  // 1% liquidation bonus taken from borrower
        aCollateralAssetParams.totalSupply = 600 ether - 4 ether;

        borrowAssetDebtTokenParams.userBalance = remainingDebt;
        borrowAssetDebtTokenParams.totalSupply = remainingDebt;

        collateralAssetParams.userBalance   = 400 ether + 4 ether;  // 1% liquidation bonus given to liquidator
        collateralAssetParams.aTokenBalance = 600 ether - 4 ether;

        borrowAssetParams.allowance     = 0;
        borrowAssetParams.userBalance   = 0;
        borrowAssetParams.aTokenBalance = 400 ether;

        _assertPoolReserveState(collateralReserveParams);
        _assertPoolReserveState(borrowReserveParams);

        _assertATokenState(aCollateralAssetParams);
        _assertDebtTokenState(borrowAssetDebtTokenParams);

        _assertAssetState(collateralAssetParams);
        _assertAssetState(borrowAssetParams);
    }

    function _loadStartingParamsAndAssertState(
        uint256 timeSinceLastUpdate,
        uint256 borrowerCollateral,
        uint256 borrowerInitialBorrow,
        uint256 liquidatorLiquidationAmount
    )
        internal returns (
            AssertPoolReserveStateParams memory collateralReserveParams,
            AssertPoolReserveStateParams memory borrowReserveParams,
            AssertATokenStateParams      memory aCollateralAssetParams,
            AssertDebtTokenStateParams   memory borrowAssetDebtTokenParams,
            AssertAssetStateParams       memory collateralAssetParams,
            AssertAssetStateParams       memory borrowAssetParams,
            uint256 borrowerDebt,
            uint256 compoundedNormalizedInterest
        )
    {
        collateralReserveParams = AssertPoolReserveStateParams({
            asset:                     address(collateralAsset),
            liquidityIndex:            1e27,
            currentLiquidityRate:      0,
            variableBorrowIndex:       1e27,
            currentVariableBorrowRate: BASE_RATE,
            currentStableBorrowRate:   0,
            lastUpdateTimestamp:       1,
            accruedToTreasury:         0,
            unbacked:                  0
        });

        borrowReserveParams = AssertPoolReserveStateParams({
            asset:                     address(borrowAsset),
            liquidityIndex:            1e27,
            currentLiquidityRate:      0.37e27,
            variableBorrowIndex:       1e27,
            currentVariableBorrowRate: 0.37e27,
            currentStableBorrowRate:   0,
            lastUpdateTimestamp:       1,
            accruedToTreasury:         0,
            unbacked:                  0
        });

        aCollateralAssetParams = AssertATokenStateParams({
            user:        borrower,
            aToken:      address(aCollateralAsset),
            userBalance: borrowerCollateral,
            totalSupply: borrowerCollateral
        });

        compoundedNormalizedInterest = _getCompoundedNormalizedInterest(0.37e27, timeSinceLastUpdate);

        borrowerDebt = (compoundedNormalizedInterest - 1e27) * borrowerInitialBorrow / 1e27;

        borrowAssetDebtTokenParams = AssertDebtTokenStateParams({
            user:        borrower,
            debtToken:   debtToken,
            userBalance: borrowerInitialBorrow + borrowerDebt,
            totalSupply: borrowerInitialBorrow + borrowerDebt
        });

        collateralAssetParams = AssertAssetStateParams({
            user:          liquidator,
            asset:         address(collateralAsset),
            allowance:     0,
            userBalance:   0,
            aTokenBalance: borrowerCollateral
        });

        borrowAssetParams = AssertAssetStateParams({
            user:          liquidator,
            asset:         address(borrowAsset),
            allowance:     liquidatorLiquidationAmount,
            userBalance:   liquidatorLiquidationAmount,
            aTokenBalance: 0
        });

        _assertPoolReserveState(collateralReserveParams);
        _assertPoolReserveState(borrowReserveParams);

        _assertATokenState(aCollateralAssetParams);
        _assertDebtTokenState(borrowAssetDebtTokenParams);

        _assertAssetState(collateralAssetParams);
        _assertAssetState(borrowAssetParams);
    }

}
