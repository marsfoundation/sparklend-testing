// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { ReserveConfiguration } from "aave-v3-core/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import { UserConfiguration }    from "aave-v3-core/contracts/protocol/libraries/configuration/UserConfiguration.sol";
import { Errors }               from "aave-v3-core/contracts/protocol/libraries/helpers/Errors.sol";
import { DataTypes }            from "aave-v3-core/contracts/protocol/libraries/types/DataTypes.sol";

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

    using UserConfiguration for DataTypes.UserConfigurationMap;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    address debtToken;

    uint256 borrowAssetId;

    function setUp() public override {
        super.setUp();

        debtToken = pool.getReserveData(address(borrowAsset)).variableDebtTokenAddress;
        borrowAssetId = pool.getReserveData(address(borrowAsset)).id;
    }

    // TODO: Add E2E tests to demonstrate protocol implications of user being underwater after liquidation

    function test_liquidationCall_01() public {
        _setUpLiquidatablePosition();

        vm.startPrank(liquidator);
        borrowAsset.mint(liquidator, 1000 ether);
        borrowAsset.approve(address(pool), 1000 ether);

        (
            AssertPoolReserveStateParams memory collateralReserveParams,
            AssertPoolReserveStateParams memory borrowReserveParams,
            AssertATokenStateParams      memory aCollateralAssetParams,
            AssertDebtTokenStateParams   memory borrowAssetDebtTokenParams,
            AssertAssetStateParams       memory collateralAssetParams,
            AssertAssetStateParams       memory borrowAssetParams,
            uint256 borrowerInterest,
            uint256 compoundedNormalizedInterest,
            uint256 expectedLiquidityIndex,
            uint256 expectedVariableBorrowIndex
        ) = _loadStartingParamsAndAssertState({
            timeSinceLastUpdate:         365 days,
            borrowerCollateral:          1000 ether,
            borrowerInitialBorrow:       500 ether,
            liquidatorLiquidationAmount: 1000 ether
        });

        assertEq(borrowerInterest, 223.445957199470228858 ether);

        assertEq(expectedLiquidityIndex,       1.37e27);
        assertEq(expectedVariableBorrowIndex,  1.446891914398940457716504e27);  // Significant difference because large APR and compounded over a year
        assertEq(compoundedNormalizedInterest, 1.446891914398940457716504e27);

        ( ,,,,, uint256 healthFactor ) = pool.getUserAccountData(borrower);

        assertEq(healthFactor, 0.691136628839690980e18);  // Less than 0.95 so full debt position is liquidatable at once

        assertEq(pool.getUserConfiguration(borrower).isBorrowing(borrowAssetId), true);

        pool.liquidationCall(address(collateralAsset), address(borrowAsset), borrower, 1000 ether, false);

        // Full debt amount of borrower liquidated (1:1 price for collateral and debtAsset, TODO: Change)
        uint256 debtLiquidated       = 500 ether + borrowerInterest;
        uint256 collateralLiquidated = debtLiquidated * 101/100 + 1;  // Rounding

        assertEq(debtLiquidated,       723.445957199470228858 ether);
        assertEq(collateralLiquidated, 730.680416771464931147 ether);

        // Remaining outstanding debt that the user owes (zero) divided by the current cash
        ( uint256 borrowRate, uint256 liquidityRate ) = _getUpdatedRates(0, debtLiquidated);

        // Back to base rate and no supplier interest
        assertEq(borrowRate,    0.05e27);
        assertEq(liquidityRate, 0);

        collateralReserveParams.lastUpdateTimestamp = 1 + 365 days;

        borrowReserveParams.liquidityIndex            = expectedLiquidityIndex;
        borrowReserveParams.currentLiquidityRate      = liquidityRate;
        borrowReserveParams.variableBorrowIndex       = expectedVariableBorrowIndex;
        borrowReserveParams.currentVariableBorrowRate = borrowRate;
        borrowReserveParams.lastUpdateTimestamp       = 1 + 365 days;

        aCollateralAssetParams.userBalance = 1000 ether - collateralLiquidated;  // 1% liquidation bonus taken from borrower (rounding)
        aCollateralAssetParams.totalSupply = 1000 ether - collateralLiquidated;

        borrowAssetDebtTokenParams.userBalance = 0;
        borrowAssetDebtTokenParams.totalSupply = 0;

        collateralAssetParams.userBalance   = collateralLiquidated;  // 1% liquidation bonus given to liquidator (rounding)
        collateralAssetParams.aTokenBalance = 1000 ether - collateralLiquidated;

        borrowAssetParams.allowance     = 1000 ether - debtLiquidated;
        borrowAssetParams.userBalance   = 1000 ether - debtLiquidated;
        borrowAssetParams.aTokenBalance = debtLiquidated;

        _assertPoolReserveState(collateralReserveParams);
        _assertPoolReserveState(borrowReserveParams);

        _assertATokenState(aCollateralAssetParams);
        _assertDebtTokenState(borrowAssetDebtTokenParams);

        _assertAssetState(collateralAssetParams);
        _assertAssetState(borrowAssetParams);

        ( ,,,,, healthFactor ) = pool.getUserAccountData(borrower);

        assertEq(healthFactor, type(uint256).max);  // User no longer has debt

        assertEq(pool.getUserConfiguration(borrower).isBorrowing(borrowAssetId), false);
    }

    function test_liquidationCall_02() public {
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
            uint256 borrowerInterest,
            uint256 compoundedNormalizedInterest,
            uint256 expectedLiquidityIndex,
            uint256 expectedVariableBorrowIndex
        ) = _loadStartingParamsAndAssertState({
            timeSinceLastUpdate:         365 days,
            borrowerCollateral:          1000 ether,
            borrowerInitialBorrow:       500 ether,
            liquidatorLiquidationAmount: 400 ether
        });

        assertEq(borrowerInterest, 223.445957199470228858 ether);

        assertEq(expectedLiquidityIndex,       1.37e27);
        assertEq(expectedVariableBorrowIndex,  1.446891914398940457716504e27);  // Significant difference because large APR and compounded over a year
        assertEq(compoundedNormalizedInterest, 1.446891914398940457716504e27);

        ( ,,,,, uint256 healthFactor ) = pool.getUserAccountData(borrower);

        assertEq(healthFactor, 0.691136628839690980e18);  // Less than 0.95 so full debt position is liquidatable at once

        assertEq(pool.getUserConfiguration(borrower).isBorrowing(borrowAssetId), true);

        pool.liquidationCall(address(collateralAsset), address(borrowAsset), borrower, 400 ether, false);

        // Remaining debt for the user is the position minus the amount liquidated plus interest accrued
        uint256 remainingDebt = 500 ether + borrowerInterest - 400 ether;

        assertEq(remainingDebt, 323.445957199470228858 ether);

        // Remaining debt that the user owes divided by the current cash (liquidated amount) plus the outstanding debt
        ( uint256 borrowRate, uint256 liquidityRate ) = _getUpdatedRates(remainingDebt, 400 ether + remainingDebt);

        assertEq(borrowRate,    0.061177267423387126110513189e27);
        assertEq(liquidityRate, 0.027351787128930695623282914e27);

        collateralReserveParams.lastUpdateTimestamp = 1 + 365 days;

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

        ( ,,,,, healthFactor ) = pool.getUserAccountData(borrower);

        assertEq(healthFactor, 0.921328566258590063e18);  // User is still underwater after liquidation

        assertEq(pool.getUserConfiguration(borrower).isBorrowing(borrowAssetId), true);
    }

    function test_liquidationCall_03() public {
        _setUpPosition();

        skip(WARP_TIME);

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
            uint256 borrowerInterest,
            uint256 compoundedNormalizedInterest,
            uint256 expectedLiquidityIndex,
            uint256 expectedVariableBorrowIndex
        ) = _loadStartingParamsAndAssertState({
            timeSinceLastUpdate:         WARP_TIME,
            borrowerCollateral:          1000 ether,
            borrowerInitialBorrow:       500 ether,
            liquidatorLiquidationAmount: 400 ether
        });

        assertEq(borrowerInterest, 1.853426710065837120 ether);  // Roughly 1% of 37% APR on 500 ether

        assertEq(expectedLiquidityIndex,       1.0037e27);
        assertEq(expectedVariableBorrowIndex,  1.003706853420131674241446640e27);
        assertEq(compoundedNormalizedInterest, 1.003706853420131674241446640e27);

        ( ,,,,, uint256 healthFactor ) = pool.getUserAccountData(borrower);

        assertEq(healthFactor, 0.996306836595396972e18);  // Greater than 0.95 so half of debt position is liquidatable at once

        pool.liquidationCall(address(collateralAsset), address(borrowAsset), borrower, 400 ether, false);

        // Liquidate half of FULL debt, not amount passed into liquidationCall
        uint256 amountLiquidated = (500 ether + borrowerInterest) / 2 + 1;  // Rounding

        assertEq(amountLiquidated, 250.926713355032918561 ether);

        // Remaining debt for the user is the position minus the amount liquidated plus interest accrued
        uint256 remainingDebt = 500 ether + borrowerInterest - amountLiquidated;

        // Exactly half of total debt is liquidated so remainingDebt == amountLiquidated
        assertEq(remainingDebt, 250.926713355032918560 ether - 1);  // Rounding

        // Remaining debt that the user owes divided by the current cash (liquidated amount) plus the outstanding debt
        ( uint256 borrowRate, uint256 liquidityRate ) = _getUpdatedRates(remainingDebt, amountLiquidated + remainingDebt);

        assertEq(borrowRate,    0.062499999999999999999950184e27);
        assertEq(liquidityRate, 0.031249999999999999999850553e27);

        collateralReserveParams.lastUpdateTimestamp = 1 + WARP_TIME;

        borrowReserveParams.liquidityIndex            = expectedLiquidityIndex;
        borrowReserveParams.currentLiquidityRate      = liquidityRate + 1;  // Rounding
        borrowReserveParams.variableBorrowIndex       = expectedVariableBorrowIndex;
        borrowReserveParams.currentVariableBorrowRate = borrowRate + 1;  // Rounding
        borrowReserveParams.lastUpdateTimestamp       = 1 + WARP_TIME;

        aCollateralAssetParams.userBalance = 1000 ether - (amountLiquidated * 101 / 100 + 1);  // 1% liquidation bonus taken from borrower (rounding)
        aCollateralAssetParams.totalSupply = 1000 ether - (amountLiquidated * 101 / 100 + 1);

        borrowAssetDebtTokenParams.userBalance = remainingDebt;
        borrowAssetDebtTokenParams.totalSupply = remainingDebt;

        collateralAssetParams.userBalance   = amountLiquidated * 101 / 100 + 1;                  // 1% liquidation bonus given to liquidator (rounding)
        collateralAssetParams.aTokenBalance = 1000 ether - (amountLiquidated * 101  / 100 + 1);  // 1% liquidation bonus given to liquidator (rounding)

        borrowAssetParams.allowance     = 400 ether - amountLiquidated;
        borrowAssetParams.userBalance   = 400 ether - amountLiquidated;
        borrowAssetParams.aTokenBalance = amountLiquidated;

        _assertPoolReserveState(collateralReserveParams);
        _assertPoolReserveState(borrowReserveParams);

        _assertATokenState(aCollateralAssetParams);
        _assertDebtTokenState(borrowAssetDebtTokenParams);

        _assertAssetState(collateralAssetParams);
        _assertAssetState(borrowAssetParams);

        ( ,,,,, healthFactor ) = pool.getUserAccountData(borrower);

        assertEq(healthFactor, 1.487613673237473184e18);  // User position is healthy again after liquidation
    }

    function test_liquidationCall_04() public {
        _setUpPosition();

        skip(WARP_TIME);

        vm.startPrank(liquidator);
        borrowAsset.mint(liquidator, 1000 ether);
        borrowAsset.approve(address(pool), 1000 ether);

        (
            AssertPoolReserveStateParams memory collateralReserveParams,
            AssertPoolReserveStateParams memory borrowReserveParams,
            AssertATokenStateParams      memory aCollateralAssetParams,
            AssertDebtTokenStateParams   memory borrowAssetDebtTokenParams,
            AssertAssetStateParams       memory collateralAssetParams,
            AssertAssetStateParams       memory borrowAssetParams,
            uint256 borrowerInterest,
            uint256 compoundedNormalizedInterest,
            uint256 expectedLiquidityIndex,
            uint256 expectedVariableBorrowIndex
        ) = _loadStartingParamsAndAssertState({
            timeSinceLastUpdate:         WARP_TIME,
            borrowerCollateral:          1000 ether,
            borrowerInitialBorrow:       500 ether,
            liquidatorLiquidationAmount: 1000 ether
        });

        assertEq(borrowerInterest, 1.853426710065837120 ether);  // Roughly 1% of 37% APR on 500 ether

        assertEq(expectedLiquidityIndex,       1.0037e27);
        assertEq(expectedVariableBorrowIndex,  1.003706853420131674241446640e27);
        assertEq(compoundedNormalizedInterest, 1.003706853420131674241446640e27);

        ( ,,,,, uint256 healthFactor ) = pool.getUserAccountData(borrower);

        assertEq(healthFactor, 0.996306836595396972e18);  // Greater than 0.95 so half of debt position is liquidatable at once

        pool.liquidationCall(address(collateralAsset), address(borrowAsset), borrower, 100 ether, false);

        // Liquidate amount specified
        uint256 amountLiquidated = 100 ether;

        // Remaining debt for the user is the position minus the amount liquidated plus interest accrued
        uint256 remainingDebt = 500 ether + borrowerInterest - amountLiquidated;

        // Exactly half of total debt is liquidated so remainingDebt == amountLiquidated
        assertEq(remainingDebt, 401.853426710065837120 ether);  // Rounding

        // Remaining debt that the user owes divided by the current cash (liquidated amount) plus the outstanding debt
        ( uint256 borrowRate, uint256 liquidityRate ) = _getUpdatedRates(remainingDebt, amountLiquidated + remainingDebt);

        assertEq(borrowRate,    0.071107949021420119560206086e27);
        assertEq(liquidityRate, 0.056938881872158411761342514e27);

        collateralReserveParams.lastUpdateTimestamp = 1 + WARP_TIME;

        borrowReserveParams.liquidityIndex            = expectedLiquidityIndex;
        borrowReserveParams.currentLiquidityRate      = liquidityRate + 1;  // Rounding
        borrowReserveParams.variableBorrowIndex       = expectedVariableBorrowIndex;
        borrowReserveParams.currentVariableBorrowRate = borrowRate + 1;  // Rounding
        borrowReserveParams.lastUpdateTimestamp       = 1 + WARP_TIME;

        aCollateralAssetParams.userBalance = 1000 ether - 101 ether;  // 1% liquidation bonus taken from borrower (rounding)
        aCollateralAssetParams.totalSupply = 1000 ether - 101 ether;

        borrowAssetDebtTokenParams.userBalance = remainingDebt + 1;  // Rounding
        borrowAssetDebtTokenParams.totalSupply = remainingDebt + 1;  // Rounding

        collateralAssetParams.userBalance   = 101 ether;               // 1% liquidation bonus given to liquidator (rounding)
        collateralAssetParams.aTokenBalance = 1000 ether - 101 ether;  // 1% liquidation bonus given to liquidator (rounding)

        borrowAssetParams.allowance     = 1000 ether - 100 ether;
        borrowAssetParams.userBalance   = 1000 ether - 100 ether;
        borrowAssetParams.aTokenBalance = 100 ether;

        _assertPoolReserveState(collateralReserveParams);
        _assertPoolReserveState(borrowReserveParams);

        _assertATokenState(aCollateralAssetParams);
        _assertDebtTokenState(borrowAssetDebtTokenParams);

        _assertAssetState(collateralAssetParams);
        _assertAssetState(borrowAssetParams);

        ( ,,,,, healthFactor ) = pool.getUserAccountData(borrower);

        assertEq(healthFactor, 1.118567044905117714e18);  // User position is healthy again after liquidation
    }

    /**********************************************************************************************/
    /*** Helper Functions                                                                       ***/
    /**********************************************************************************************/

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
            uint256 borrowerInterest,
            uint256 compoundedNormalizedInterest,
            uint256 expectedLiquidityIndex,
            uint256 expectedVariableBorrowIndex
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

        borrowerInterest = (compoundedNormalizedInterest - 1e27) * borrowerInitialBorrow / 1e27;

        expectedLiquidityIndex      = 1e27 + (1e27 * 0.37e27 * timeSinceLastUpdate / 365 days / 1e27);
        expectedVariableBorrowIndex = 1e27 * compoundedNormalizedInterest / 1e27;

        borrowAssetDebtTokenParams = AssertDebtTokenStateParams({
            user:        borrower,
            debtToken:   debtToken,
            userBalance: borrowerInitialBorrow + borrowerInterest,
            totalSupply: borrowerInitialBorrow + borrowerInterest
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
        _assertDebtTokenState({ params: borrowAssetDebtTokenParams, tolerance: 1 });  // Allow rounding because of interest calculation

        _assertAssetState(collateralAssetParams);
        _assertAssetState(borrowAssetParams);
    }

}
