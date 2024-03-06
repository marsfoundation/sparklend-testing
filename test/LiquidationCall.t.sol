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
    uint256 collateralAssetId;

    uint256 start;

    struct State {
        AssertPoolReserveStateParams collateralReserveParams;
        AssertPoolReserveStateParams borrowReserveParams;
        AssertATokenStateParams      aCollateralAssetParams;
        AssertDebtTokenStateParams   borrowAssetDebtTokenParams;
        AssertAssetStateParams       collateralAssetParams;
        AssertAssetStateParams       borrowAssetParams;
    }

    function setUp() public override {
        super.setUp();

        debtToken         = pool.getReserveData(address(borrowAsset)).variableDebtTokenAddress;
        borrowAssetId     = pool.getReserveData(address(borrowAsset)).id;
        collateralAssetId = pool.getReserveData(address(collateralAsset)).id;

        start = block.timestamp;

        // All tests working against the same 1000 collateral / 500 initial borrow position
        _setUpPosition();
    }

    modifier whenProtocolFeeIsZero { _; }

    modifier whenProtocolFeeIsNotZero {
        vm.prank(admin);
        poolConfigurator.setLiquidationProtocolFee(address(collateralAsset), 20_00);  // 20%
        _;
    }

    modifier whenUserHealthFactorBelowCloseFactorThreshold {
        skip(365 days);

        ( ,,,,, uint256 healthFactor ) = pool.getUserAccountData(borrower);
        assertLt(healthFactor, 0.95e18);  // Less than 0.95 so full debt position is liquidatable at once

        _;
    }

    modifier whenUserHFAboveCloseFactorThreshold {
        skip(WARP_TIME);

        ( ,,,,, uint256 healthFactor ) = pool.getUserAccountData(borrower);
        assertGt(healthFactor, 0.95e18);  // Greater than 0.95 so half of debt position is liquidatable at once
        assertLt(healthFactor, 1e18);

        _;
    }

    modifier whenAmountGtAvailableDebt { _; }

    modifier whenAmountLteAvailableDebt { _; }

    modifier whenUserDebtGtCollateral {
        vm.warp(1 + 1000 days);

        uint256 aTokenBalance    = aCollateralAsset.balanceOf(borrower);
        uint256 debtTokenBalance = IERC20(debtToken).balanceOf(borrower);

        assertGt(debtTokenBalance, aTokenBalance);

        _;
    }

    modifier whenUserDebtLtCollateral {
        uint256 aTokenBalance    = aCollateralAsset.balanceOf(borrower);
        uint256 debtTokenBalance = IERC20(debtToken).balanceOf(borrower);

        assertLt(debtTokenBalance, aTokenBalance);

        _;
    }

    struct Params {
        uint256 liquidationAmount;
        uint256 startingCollateral;
        uint256 startingBorrow;
        uint256 borrowerDebt;
        uint256 debtLiquidated;
        uint256 collateralLiquidated;
        uint256 protocolFee;
        uint256 remainingDebt;
        uint256 healthFactor;
        uint256 borrowIndex;
        uint256 liquidityIndex;
        uint256 resultingBorrowRate;
        uint256 resultingLiquidityRate;
        uint256 updateTimestamp;
        bool    isBorrowing;
        bool    isUsingAsCollateral;
    }

    function _runLiquidationTest(Params memory params) internal {
        vm.startPrank(liquidator);
        borrowAsset.mint(liquidator, params.liquidationAmount);
        borrowAsset.approve(address(pool), params.liquidationAmount);

        (
            State memory state,
            uint256 borrowerInterest,
            uint256 compoundedNormalizedInterest,
            uint256 expectedLiquidityIndex,
            uint256 expectedVariableBorrowIndex
        ) = _loadStartingParamsAndAssertState({
            timeSinceLastUpdate:         params.updateTimestamp - start,
            borrowerCollateral:          params.startingCollateral,
            borrowerInitialBorrow:       params.startingBorrow,
            liquidatorLiquidationAmount: params.liquidationAmount
        });

        assertEq(params.borrowerDebt, IERC20(debtToken).balanceOf(borrower), "borrowerDebt");

        assertApproxEqAbs(borrowerInterest, params.borrowerDebt - params.startingBorrow, 2, "borrowerInterest");

        // Calculated values and expected values are within 1e-27 of each other
        assertApproxEqAbs(expectedLiquidityIndex,       params.liquidityIndex, 1, "expectedLiquidityIndex");
        assertApproxEqAbs(expectedVariableBorrowIndex,  params.borrowIndex,    1, "expectedVariableBorrowIndex");
        assertApproxEqAbs(compoundedNormalizedInterest, params.borrowIndex,    1, "compoundedNormalizedInterest");  // Always the same because this is the first update

        assertEq(pool.getUserConfiguration(borrower).isBorrowing(borrowAssetId),             true);
        assertEq(pool.getUserConfiguration(borrower).isUsingAsCollateral(collateralAssetId), true);

        pool.liquidationCall(
            address(collateralAsset),
            address(borrowAsset),
            borrower,
            params.liquidationAmount,
            false
        );

        // Remaining outstanding debt that the user owes divided by the current cash (liquidated amount) plus the outstanding debt
        ( uint256 borrowRate, uint256 liquidityRate )
            = _getUpdatedRates(params.remainingDebt, params.debtLiquidated + params.remainingDebt);

        // Calculated values and expected values are within 2e-27 of each other
        assertApproxEqAbs(borrowRate,    params.resultingBorrowRate,    2, "borrowRate");
        assertApproxEqAbs(liquidityRate, params.resultingLiquidityRate, 2, "liquidityRate");

        state.collateralReserveParams.lastUpdateTimestamp = params.updateTimestamp;

        state.borrowReserveParams.liquidityIndex            = params.liquidityIndex;
        state.borrowReserveParams.currentLiquidityRate      = params.resultingLiquidityRate;
        state.borrowReserveParams.variableBorrowIndex       = params.borrowIndex;
        state.borrowReserveParams.currentVariableBorrowRate = params.resultingBorrowRate;
        state.borrowReserveParams.lastUpdateTimestamp       = params.updateTimestamp;

        state.aCollateralAssetParams.userBalance = params.startingCollateral - params.collateralLiquidated;
        state.aCollateralAssetParams.totalSupply = params.startingCollateral - params.collateralLiquidated + params.protocolFee;

        // Perform manual assertion of treasury aToken transfer
        // Treasury gets minted aTokens corresponding to underlying collateralAsset that got transferred to aToken
        assertEq(aCollateralAsset.balanceOf(treasury), params.protocolFee, "protocolFee");

        state.borrowAssetDebtTokenParams.userBalance = params.remainingDebt;
        state.borrowAssetDebtTokenParams.totalSupply = params.remainingDebt;

        state.collateralAssetParams.userBalance   = params.collateralLiquidated - params.protocolFee;
        state.collateralAssetParams.aTokenBalance = params.startingCollateral - params.collateralLiquidated + params.protocolFee;

        state.borrowAssetParams.allowance     = params.liquidationAmount - params.debtLiquidated;
        state.borrowAssetParams.userBalance   = params.liquidationAmount - params.debtLiquidated;
        state.borrowAssetParams.aTokenBalance = params.debtLiquidated;

        _assertPoolReserveState(state.collateralReserveParams);
        _assertPoolReserveState(state.borrowReserveParams);

        _assertATokenState(state.aCollateralAssetParams);
        _assertDebtTokenState(state.borrowAssetDebtTokenParams);

        _assertAssetState(state.collateralAssetParams);
        _assertAssetState(state.borrowAssetParams);

        ( ,,,,, uint256 healthFactor ) = pool.getUserAccountData(borrower);

        assertEq(healthFactor, params.healthFactor);

        assertEq(
            pool.getUserConfiguration(borrower).isBorrowing(borrowAssetId),
            params.isBorrowing,
            "isBorrowing"
        );

        assertEq(
            pool.getUserConfiguration(borrower).isUsingAsCollateral(collateralAssetId),
            params.isUsingAsCollateral,
            "isUsingAsCollateral"
        );
    }

    // TODO: Add E2E tests to demonstrate protocol implications of user being underwater after liquidation

    function test_liquidationCall_01()
        public
        whenProtocolFeeIsZero
        whenUserHealthFactorBelowCloseFactorThreshold
        whenAmountGtAvailableDebt
    {
        Params memory params;

        params.startingCollateral = 1000 ether;
        params.startingBorrow     = 500 ether;

        params.liquidationAmount    = 800 ether;
        params.borrowerDebt         = 723.445957199470228858 ether; // 500 ether + 37% APR over 365 days
        params.debtLiquidated       = 723.445957199470228858 ether;
        params.collateralLiquidated = 730.680416771464931147 ether;
        params.remainingDebt        = 0;
        params.healthFactor         = type(uint256).max;  // User has no more debt

        params.liquidityIndex         = 1.37e27;  // Full utilization for a full year
        params.borrowIndex            = 1.446891914398940457716504e27;  // Significant difference because large APR and compounded over a year
        params.resultingBorrowRate    = 0.05e27;  // All debt removed so back to base rate
        params.resultingLiquidityRate = 0;
        params.updateTimestamp        = 1 + 365 days;

        params.isBorrowing         = false;
        params.isUsingAsCollateral = true;

        // 10% liquidation bonus goes to the liquidator (rounding)
        assertApproxEqAbs(params.collateralLiquidated, params.debtLiquidated * 101/100, 1);

        _runLiquidationTest(params);
    }

    function test_liquidationCall_02()
        public
        whenProtocolFeeIsZero
        whenUserHealthFactorBelowCloseFactorThreshold
        whenAmountLteAvailableDebt
        whenUserDebtGtCollateral
    {
        Params memory params;

        params.startingCollateral = 1000 ether;
        params.startingBorrow     = 500 ether;

        params.liquidationAmount    = 1200 ether;
        params.borrowerDebt         = 1350.548092145123279590 ether; // Total debt > collateral (1350 > 1000)
        params.debtLiquidated       = 990.099009900990099010 ether;  // 10% liquidation bonus has to be reduced from debt side when liquidating all collateral
        params.collateralLiquidated = 1000 ether;
        params.remainingDebt        = 360.449082244133180581 ether;  // Bad debt because user has no collateral after liquidation
        params.healthFactor         = 0;  // HF goes to zero when there is no collateral backing debt

        params.liquidityIndex         = 2.013698630136986301369863013e27;  // 1000/365 x 37%
        params.borrowIndex            = 2.701096184290246559179463013e27;  // Significant difference because large APR and compounded over a year
        params.resultingBorrowRate    = 0.056672274100058502185344188e27;  // Borrow rate above base
        params.resultingLiquidityRate = 0.015125317866769464179973745e27;  // Liquidity rate above zero because of bad debt
        params.updateTimestamp        = 1 + 1000 days;

        params.isBorrowing         = true;   // User is technically still borrowing but have no incentive to repay
        params.isUsingAsCollateral = false;  // User has no collateral after liquidation

        // 10% liquidation bonus goes to the liquidator (rounding)
        assertApproxEqAbs(params.debtLiquidated, uint256(params.collateralLiquidated * 100)/101, 1);

        assertApproxEqAbs(params.remainingDebt, params.borrowerDebt - params.debtLiquidated, 1);

        _runLiquidationTest(params);
    }

    function test_liquidationCall_03()
        public
        whenProtocolFeeIsZero
        whenUserHealthFactorBelowCloseFactorThreshold
        whenAmountLteAvailableDebt
        whenUserDebtLtCollateral
    {
        Params memory params;

        params.startingCollateral = 1000 ether;
        params.startingBorrow     = 500 ether;

        params.liquidationAmount    = 400 ether;
        params.borrowerDebt         = 723.445957199470228858 ether; // 500 ether + 37% APR over 365 days
        params.debtLiquidated       = 400 ether;
        params.collateralLiquidated = 404 ether;  // 10% liquidation bonus
        params.remainingDebt        = 323.445957199470228858 ether;
        params.healthFactor         = 0.921328566258590063e18;  // User position is still unhealthy

        params.liquidityIndex         = 1.37e27;  // Full utilization for a full year
        params.borrowIndex            = 1.446891914398940457716504e27;  // Significant difference because large APR and compounded over a year
        params.resultingBorrowRate    = 0.061177267423387126110513189e27;
        params.resultingLiquidityRate = 0.027351787128930695623282915e27;
        params.updateTimestamp        = 1 + 365 days;

        params.isBorrowing         = true;
        params.isUsingAsCollateral = true;

        // 10% liquidation bonus goes to the liquidator (rounding)
        assertApproxEqAbs(params.collateralLiquidated, params.debtLiquidated * 101/100, 1);

        assertEq(params.remainingDebt, params.borrowerDebt - 400 ether);

        _runLiquidationTest(params);
    }

    function test_liquidationCall_04()
        public
        whenProtocolFeeIsZero
        whenUserHFAboveCloseFactorThreshold
        whenAmountGtAvailableDebt
    {
        Params memory params;

        params.startingCollateral = 1000 ether;
        params.startingBorrow     = 500 ether;

        params.liquidationAmount    = 300 ether;  // Just above available debt (half)
        params.borrowerDebt         = 501.853426710065837121 ether; // 500 ether + 37% APR over 3.65 days
        params.debtLiquidated       = 250.926713355032918561 ether;
        params.collateralLiquidated = 253.435980488583247747 ether;
        params.remainingDebt        = 250.926713355032918559 ether;
        params.healthFactor         = 1.487613673237473184e18;  // User has no more debt

        params.liquidityIndex         = 1.0037e27;  // Full utilization for a 1% of a year
        params.borrowIndex            = 1.003706853420131674241446640e27;  // Smaller difference because compounded over a shorter period
        params.resultingBorrowRate    = 0.062499999999999999999950185e27;
        params.resultingLiquidityRate = 0.031249999999999999999850554e27;
        params.updateTimestamp        = 1 + WARP_TIME;

        params.isBorrowing         = true;
        params.isUsingAsCollateral = true;

        // 10% liquidation bonus goes to the liquidator (rounding)
        assertApproxEqAbs(params.collateralLiquidated, params.debtLiquidated * 101/100, 1);

        // Half of debt is liquidated when HF is above close factor threshold (0.95)
        assertApproxEqAbs(params.remainingDebt, params.borrowerDebt / 2, 1);

        _runLiquidationTest(params);
    }

    function test_liquidationCall_05()
        public
        whenProtocolFeeIsZero
        whenUserHFAboveCloseFactorThreshold
        whenAmountLteAvailableDebt
    {
        Params memory params;

        params.startingCollateral = 1000 ether;
        params.startingBorrow     = 500 ether;

        params.liquidationAmount    = 200 ether;  // Just below available debt (half)
        params.borrowerDebt         = 501.853426710065837121 ether; // 500 ether + 37% APR over 3.65 days
        params.debtLiquidated       = 200 ether;
        params.collateralLiquidated = 202 ether;
        params.remainingDebt        = 301.853426710065837121 ether;
        params.healthFactor         = 1.321833594366751193e18;

        params.liquidityIndex         = 1.0037e27;  // Full utilization for a 1% of a year
        params.borrowIndex            = 1.003706853420131674241446640e27;  // Smaller difference because compounded over a shorter period
        params.resultingBorrowRate    = 0.065036931634047337318693389e27;
        params.resultingLiquidityRate = 0.039118235786775215677621216e27;
        params.updateTimestamp        = 1 + WARP_TIME;

        params.isBorrowing         = true;
        params.isUsingAsCollateral = true;

        // 10% liquidation bonus goes to the liquidator (rounding)
        assertApproxEqAbs(params.collateralLiquidated, params.debtLiquidated * 101/100, 1);

        // Specified debt is liquidated
        assertApproxEqAbs(params.remainingDebt, params.borrowerDebt - 200 ether, 1);

        _runLiquidationTest(params);
    }

    function test_liquidationCall_06()
        public
        whenProtocolFeeIsNotZero
        whenUserHealthFactorBelowCloseFactorThreshold
        whenAmountGtAvailableDebt
    {
        Params memory params;

        params.startingCollateral = 1000 ether;
        params.startingBorrow     = 500 ether;

        params.liquidationAmount    = 800 ether;
        params.borrowerDebt         = 723.445957199470228858 ether; // 500 ether + 37% APR over 365 days
        params.debtLiquidated       = 723.445957199470228858 ether;
        params.collateralLiquidated = 730.680416771464931147 ether;
        params.protocolFee          = 1.446891914398940458 ether;
        params.remainingDebt        = 0;
        params.healthFactor         = type(uint256).max;  // User has no more debt

        params.liquidityIndex         = 1.37e27;  // Full utilization for a full year
        params.borrowIndex            = 1.446891914398940457716504e27;  // Significant difference because large APR and compounded over a year
        params.resultingBorrowRate    = 0.05e27;  // All debt removed so back to base rate
        params.resultingLiquidityRate = 0;
        params.updateTimestamp        = 1 + 365 days;

        params.isBorrowing         = false;
        params.isUsingAsCollateral = true;

        // 10% liquidation bonus goes to the liquidator (rounding)
        assertApproxEqAbs(params.collateralLiquidated, params.debtLiquidated * 101/100, 1);

        // Protocol fee is 20% of the bonus collateral amount (below calc uses 1:1 pricing)
        assertApproxEqAbs(params.protocolFee, (params.collateralLiquidated - params.debtLiquidated) * 20/100, 1);

        _runLiquidationTest(params);
    }

    function test_liquidationCall_07()
        public
        whenProtocolFeeIsNotZero
        whenUserHealthFactorBelowCloseFactorThreshold
        whenAmountLteAvailableDebt
        whenUserDebtGtCollateral
    {
        Params memory params;

        params.startingCollateral = 1000 ether;
        params.startingBorrow     = 500 ether;

        params.liquidationAmount    = 1200 ether;
        params.borrowerDebt         = 1350.548092145123279590 ether; // Total debt > collateral (1350 > 1000)
        params.debtLiquidated       = 990.099009900990099010 ether;  // 10% liquidation bonus has to be reduced from debt side when liquidating all collateral
        params.collateralLiquidated = 1000 ether;
        params.protocolFee          = 1.980198019801980198 ether;
        params.remainingDebt        = 360.449082244133180581 ether;  // Bad debt because user has no collateral after liquidation
        params.healthFactor         = 0;  // HF goes to zero when there is no collateral backing debt

        params.liquidityIndex         = 2.013698630136986301369863013e27;  // 1000/365 x 37%
        params.borrowIndex            = 2.701096184290246559179463013e27;  // Significant difference because large APR and compounded over a year
        params.resultingBorrowRate    = 0.056672274100058502185344188e27;  // Borrow rate above base
        params.resultingLiquidityRate = 0.015125317866769464179973745e27;  // Liquidity rate above zero because of bad debt
        params.updateTimestamp        = 1 + 1000 days;

        params.isBorrowing         = true;   // User is technically still borrowing but have no incentive to repay
        params.isUsingAsCollateral = false;  // User has no collateral after liquidation

        // 10% liquidation bonus goes to the liquidator (rounding)
        assertApproxEqAbs(params.debtLiquidated, uint256(params.collateralLiquidated * 100)/101, 1);

        // Protocol fee is 20% of the bonus collateral amount (below calc uses 1:1 pricing)
        assertApproxEqAbs(params.protocolFee, (params.collateralLiquidated - params.debtLiquidated) * 20/100, 1);

        assertApproxEqAbs(params.remainingDebt, params.borrowerDebt - params.debtLiquidated, 1);

        _runLiquidationTest(params);
    }

    function test_liquidationCall_08()
        public
        whenProtocolFeeIsNotZero
        whenUserHealthFactorBelowCloseFactorThreshold
        whenAmountLteAvailableDebt
        whenUserDebtLtCollateral
    {
        Params memory params;

        params.startingCollateral = 1000 ether;
        params.startingBorrow     = 500 ether;

        params.liquidationAmount    = 400 ether;
        params.borrowerDebt         = 723.445957199470228858 ether; // 500 ether + 37% APR over 365 days
        params.debtLiquidated       = 400 ether;
        params.collateralLiquidated = 404 ether;  // 10% liquidation bonus
        params.protocolFee          = 0.8 ether;
        params.remainingDebt        = 323.445957199470228858 ether;
        params.healthFactor         = 0.921328566258590063e18;  // User position is still unhealthy

        params.liquidityIndex         = 1.37e27;  // Full utilization for a full year
        params.borrowIndex            = 1.446891914398940457716504e27;  // Significant difference because large APR and compounded over a year
        params.resultingBorrowRate    = 0.061177267423387126110513189e27;
        params.resultingLiquidityRate = 0.027351787128930695623282915e27;
        params.updateTimestamp        = 1 + 365 days;

        params.isBorrowing         = true;
        params.isUsingAsCollateral = true;

        // 10% liquidation bonus goes to the liquidator (rounding)
        assertApproxEqAbs(params.collateralLiquidated, params.debtLiquidated * 101/100, 1);

        // Protocol fee is 20% of the bonus collateral amount (below calc uses 1:1 pricing)
        assertApproxEqAbs(params.protocolFee, (params.collateralLiquidated - params.debtLiquidated) * 20/100, 1);

        assertEq(params.remainingDebt, params.borrowerDebt - 400 ether);

        _runLiquidationTest(params);
    }

    function test_liquidationCall_09()
        public
        whenProtocolFeeIsNotZero
        whenUserHFAboveCloseFactorThreshold
        whenAmountGtAvailableDebt
    {
        Params memory params;

        params.startingCollateral = 1000 ether;
        params.startingBorrow     = 500 ether;

        params.liquidationAmount    = 300 ether;  // Just above available debt (half)
        params.borrowerDebt         = 501.853426710065837121 ether; // 500 ether + 37% APR over 3.65 days
        params.debtLiquidated       = 250.926713355032918561 ether;
        params.collateralLiquidated = 253.435980488583247747 ether;
        params.protocolFee          = 0.501853426710065837 ether;
        params.remainingDebt        = 250.926713355032918559 ether;
        params.healthFactor         = 1.487613673237473184e18;  // User has no more debt

        params.liquidityIndex         = 1.0037e27;  // Full utilization for a 1% of a year
        params.borrowIndex            = 1.003706853420131674241446640e27;  // Smaller difference because compounded over a shorter period
        params.resultingBorrowRate    = 0.062499999999999999999950185e27;
        params.resultingLiquidityRate = 0.031249999999999999999850554e27;
        params.updateTimestamp        = 1 + WARP_TIME;

        params.isBorrowing         = true;
        params.isUsingAsCollateral = true;

        // 10% liquidation bonus goes to the liquidator (rounding)
        assertApproxEqAbs(params.collateralLiquidated, params.debtLiquidated * 101/100, 1);

        // Protocol fee is 20% of the bonus collateral amount (below calc uses 1:1 pricing)
        assertApproxEqAbs(params.protocolFee, (params.collateralLiquidated - params.debtLiquidated) * 20/100, 1);

        // Half of debt is liquidated when HF is above close factor threshold (0.95)
        assertApproxEqAbs(params.remainingDebt, params.borrowerDebt / 2, 1);

        _runLiquidationTest(params);
    }

    function test_liquidationCall_10()
        public
        whenProtocolFeeIsNotZero
        whenUserHFAboveCloseFactorThreshold
        whenAmountLteAvailableDebt
    {
        Params memory params;

        params.startingCollateral = 1000 ether;
        params.startingBorrow     = 500 ether;

        params.liquidationAmount    = 200 ether;  // Just below available debt (half)
        params.borrowerDebt         = 501.853426710065837121 ether; // 500 ether + 37% APR over 3.65 days
        params.debtLiquidated       = 200 ether;
        params.collateralLiquidated = 202 ether;
        params.protocolFee          = 0.4 ether;
        params.remainingDebt        = 301.853426710065837121 ether;
        params.healthFactor         = 1.321833594366751193e18;

        params.liquidityIndex         = 1.0037e27;  // Full utilization for a 1% of a year
        params.borrowIndex            = 1.003706853420131674241446640e27;  // Smaller difference because compounded over a shorter period
        params.resultingBorrowRate    = 0.065036931634047337318693389e27;
        params.resultingLiquidityRate = 0.039118235786775215677621216e27;
        params.updateTimestamp        = 1 + WARP_TIME;

        params.isBorrowing         = true;
        params.isUsingAsCollateral = true;

        // 10% liquidation bonus goes to the liquidator (rounding)
        assertApproxEqAbs(params.collateralLiquidated, params.debtLiquidated * 101/100, 1);

        // Protocol fee is 20% of the bonus collateral amount (below calc uses 1:1 pricing)
        assertApproxEqAbs(params.protocolFee, (params.collateralLiquidated - params.debtLiquidated) * 20/100, 1);

        // Specified debt is liquidated
        assertApproxEqAbs(params.remainingDebt, params.borrowerDebt - 200 ether, 1);

        _runLiquidationTest(params);
    }


    // function test_liquidationCall_02()
    //     public
    //     whenProtocolFeeIsZero
    //     whenUserHealthFactorBelowCloseFactorThreshold
    // {
    //     vm.startPrank(liquidator);
    //     borrowAsset.mint(liquidator, 400 ether);
    //     borrowAsset.approve(address(pool), 400 ether);

    //     (
    //         AssertPoolReserveStateParams memory collateralReserveParams,
    //         AssertPoolReserveStateParams memory borrowReserveParams,
    //         AssertATokenStateParams      memory aCollateralAssetParams,
    //         AssertDebtTokenStateParams   memory borrowAssetDebtTokenParams,
    //         AssertAssetStateParams       memory collateralAssetParams,
    //         AssertAssetStateParams       memory borrowAssetParams,
    //         uint256 borrowerInterest,
    //         uint256 compoundedNormalizedInterest,
    //         uint256 expectedLiquidityIndex,
    //         uint256 expectedVariableBorrowIndex
    //     ) = _loadStartingParamsAndAssertState({
    //         timeSinceLastUpdate:         365 days,
    //         borrowerCollateral:          1000 ether,
    //         borrowerInitialBorrow:       500 ether,
    //         liquidatorLiquidationAmount: 400 ether
    //     });

    //     assertEq(borrowerInterest, 223.445957199470228858 ether);

    //     assertEq(expectedLiquidityIndex,       1.37e27);
    //     assertEq(expectedVariableBorrowIndex,  1.446891914398940457716504e27);  // Significant difference because large APR and compounded over a year
    //     assertEq(compoundedNormalizedInterest, 1.446891914398940457716504e27);

    //     ( ,,,,, uint256 healthFactor ) = pool.getUserAccountData(borrower);

    //     assertEq(healthFactor, 0.691136628839690980e18);  // Less than 0.95 so full debt position is liquidatable at once

    //     assertEq(pool.getUserConfiguration(borrower).isBorrowing(borrowAssetId), true);

    //     pool.liquidationCall(address(collateralAsset), address(borrowAsset), borrower, 400 ether, false);

    //     // Remaining debt for the user is the position minus the amount liquidated plus interest accrued
    //     uint256 remainingDebt = 500 ether + borrowerInterest - 400 ether;

    //     assertEq(remainingDebt, 323.445957199470228858 ether);

    //     // Remaining debt that the user owes divided by the current cash (liquidated amount) plus the outstanding debt
    //     ( uint256 borrowRate, uint256 liquidityRate ) = _getUpdatedRates(remainingDebt, 400 ether + remainingDebt);

    //     assertEq(borrowRate,    0.061177267423387126110513189e27);
    //     assertEq(liquidityRate, 0.027351787128930695623282914e27);

    //     collateralReserveParams.lastUpdateTimestamp = 1 + 365 days;

    //     borrowReserveParams.liquidityIndex            = expectedLiquidityIndex;
    //     borrowReserveParams.currentLiquidityRate      = liquidityRate + 1;  // Rounding
    //     borrowReserveParams.variableBorrowIndex       = expectedVariableBorrowIndex;
    //     borrowReserveParams.currentVariableBorrowRate = borrowRate;
    //     borrowReserveParams.lastUpdateTimestamp       = 1 + 365 days;

    //     aCollateralAssetParams.userBalance = 600 ether - 4 ether;  // 1% liquidation bonus taken from borrower
    //     aCollateralAssetParams.totalSupply = 600 ether - 4 ether;

    //     borrowAssetDebtTokenParams.userBalance = remainingDebt;
    //     borrowAssetDebtTokenParams.totalSupply = remainingDebt;

    //     collateralAssetParams.userBalance   = 400 ether + 4 ether;  // 1% liquidation bonus given to liquidator
    //     collateralAssetParams.aTokenBalance = 600 ether - 4 ether;

    //     borrowAssetParams.allowance     = 0;
    //     borrowAssetParams.userBalance   = 0;
    //     borrowAssetParams.aTokenBalance = 400 ether;

    //     _assertPoolReserveState(collateralReserveParams);
    //     _assertPoolReserveState(borrowReserveParams);

    //     _assertATokenState(aCollateralAssetParams);
    //     _assertDebtTokenState(borrowAssetDebtTokenParams);

    //     _assertAssetState(collateralAssetParams);
    //     _assertAssetState(borrowAssetParams);

    //     ( ,,,,, healthFactor ) = pool.getUserAccountData(borrower);

    //     assertEq(healthFactor, 0.921328566258590063e18);  // User is still underwater after liquidation

    //     assertEq(pool.getUserConfiguration(borrower).isBorrowing(borrowAssetId), true);
    // }

    // function test_liquidationCall_03() public {
    //     skip(WARP_TIME);

    //     vm.startPrank(liquidator);
    //     borrowAsset.mint(liquidator, 400 ether);
    //     borrowAsset.approve(address(pool), 400 ether);

    //     (
    //         AssertPoolReserveStateParams memory collateralReserveParams,
    //         AssertPoolReserveStateParams memory borrowReserveParams,
    //         AssertATokenStateParams      memory aCollateralAssetParams,
    //         AssertDebtTokenStateParams   memory borrowAssetDebtTokenParams,
    //         AssertAssetStateParams       memory collateralAssetParams,
    //         AssertAssetStateParams       memory borrowAssetParams,
    //         uint256 borrowerInterest,
    //         uint256 compoundedNormalizedInterest,
    //         uint256 expectedLiquidityIndex,
    //         uint256 expectedVariableBorrowIndex
    //     ) = _loadStartingParamsAndAssertState({
    //         timeSinceLastUpdate:         WARP_TIME,
    //         borrowerCollateral:          1000 ether,
    //         borrowerInitialBorrow:       500 ether,
    //         liquidatorLiquidationAmount: 400 ether
    //     });

    //     assertEq(borrowerInterest, 1.853426710065837120 ether);  // Roughly 1% of 37% APR on 500 ether

    //     assertEq(expectedLiquidityIndex,       1.0037e27);
    //     assertEq(expectedVariableBorrowIndex,  1.003706853420131674241446640e27);
    //     assertEq(compoundedNormalizedInterest, 1.003706853420131674241446640e27);

    //     ( ,,,,, uint256 healthFactor ) = pool.getUserAccountData(borrower);

    //     assertEq(healthFactor, 0.996306836595396972e18);  // Greater than 0.95 so half of debt position is liquidatable at once

    //     pool.liquidationCall(address(collateralAsset), address(borrowAsset), borrower, 400 ether, false);

    //     // Liquidate half of FULL debt, not amount passed into liquidationCall
    //     uint256 amountLiquidated = (500 ether + borrowerInterest) / 2 + 1;  // Rounding

    //     assertEq(amountLiquidated, 250.926713355032918561 ether);

    //     // Remaining debt for the user is the position minus the amount liquidated plus interest accrued
    //     uint256 remainingDebt = 500 ether + borrowerInterest - amountLiquidated;

    //     // Exactly half of total debt is liquidated so remainingDebt == amountLiquidated
    //     assertEq(remainingDebt, 250.926713355032918560 ether - 1);  // Rounding

    //     // Remaining debt that the user owes divided by the current cash (liquidated amount) plus the outstanding debt
    //     ( uint256 borrowRate, uint256 liquidityRate ) = _getUpdatedRates(remainingDebt, amountLiquidated + remainingDebt);

    //     assertEq(borrowRate,    0.062499999999999999999950184e27);
    //     assertEq(liquidityRate, 0.031249999999999999999850553e27);

    //     collateralReserveParams.lastUpdateTimestamp = 1 + WARP_TIME;

    //     borrowReserveParams.liquidityIndex            = expectedLiquidityIndex;
    //     borrowReserveParams.currentLiquidityRate      = liquidityRate + 1;  // Rounding
    //     borrowReserveParams.variableBorrowIndex       = expectedVariableBorrowIndex;
    //     borrowReserveParams.currentVariableBorrowRate = borrowRate + 1;  // Rounding
    //     borrowReserveParams.lastUpdateTimestamp       = 1 + WARP_TIME;

    //     aCollateralAssetParams.userBalance = 1000 ether - (amountLiquidated * 101 / 100 + 1);  // 1% liquidation bonus taken from borrower (rounding)
    //     aCollateralAssetParams.totalSupply = 1000 ether - (amountLiquidated * 101 / 100 + 1);

    //     borrowAssetDebtTokenParams.userBalance = remainingDebt;
    //     borrowAssetDebtTokenParams.totalSupply = remainingDebt;

    //     collateralAssetParams.userBalance   = amountLiquidated * 101 / 100 + 1;                  // 1% liquidation bonus given to liquidator (rounding)
    //     collateralAssetParams.aTokenBalance = 1000 ether - (amountLiquidated * 101  / 100 + 1);  // 1% liquidation bonus given to liquidator (rounding)

    //     borrowAssetParams.allowance     = 400 ether - amountLiquidated;
    //     borrowAssetParams.userBalance   = 400 ether - amountLiquidated;
    //     borrowAssetParams.aTokenBalance = amountLiquidated;

    //     _assertPoolReserveState(collateralReserveParams);
    //     _assertPoolReserveState(borrowReserveParams);

    //     _assertATokenState(aCollateralAssetParams);
    //     _assertDebtTokenState(borrowAssetDebtTokenParams);

    //     _assertAssetState(collateralAssetParams);
    //     _assertAssetState(borrowAssetParams);

    //     ( ,,,,, healthFactor ) = pool.getUserAccountData(borrower);

    //     assertEq(healthFactor, 1.487613673237473184e18);  // User position is healthy again after liquidation
    // }

    // function test_liquidationCall_04() public {
    //     skip(WARP_TIME);

    //     vm.startPrank(liquidator);
    //     borrowAsset.mint(liquidator, 1000 ether);
    //     borrowAsset.approve(address(pool), 1000 ether);

    //     (
    //         AssertPoolReserveStateParams memory collateralReserveParams,
    //         AssertPoolReserveStateParams memory borrowReserveParams,
    //         AssertATokenStateParams      memory aCollateralAssetParams,
    //         AssertDebtTokenStateParams   memory borrowAssetDebtTokenParams,
    //         AssertAssetStateParams       memory collateralAssetParams,
    //         AssertAssetStateParams       memory borrowAssetParams,
    //         uint256 borrowerInterest,
    //         uint256 compoundedNormalizedInterest,
    //         uint256 expectedLiquidityIndex,
    //         uint256 expectedVariableBorrowIndex
    //     ) = _loadStartingParamsAndAssertState({
    //         timeSinceLastUpdate:         WARP_TIME,
    //         borrowerCollateral:          1000 ether,
    //         borrowerInitialBorrow:       500 ether,
    //         liquidatorLiquidationAmount: 1000 ether
    //     });

    //     borrowerInterest += 1;  // Rounding

    //     assertEq(borrowerInterest, 1.853426710065837121 ether);  // Roughly 1% of 37% APR on 500 ether

    //     assertEq(expectedLiquidityIndex,       1.0037e27);
    //     assertEq(expectedVariableBorrowIndex,  1.003706853420131674241446640e27);
    //     assertEq(compoundedNormalizedInterest, 1.003706853420131674241446640e27);

    //     ( ,,,,, uint256 healthFactor ) = pool.getUserAccountData(borrower);

    //     assertEq(healthFactor, 0.996306836595396972e18);  // Greater than 0.95 so half of debt position is liquidatable at once

    //     pool.liquidationCall(address(collateralAsset), address(borrowAsset), borrower, 100 ether, false);

    //     // Liquidate amount specified
    //     uint256 amountLiquidated = 100 ether;

    //     // Remaining debt for the user is the position minusf the amount liquidated plus interest accrued
    //     uint256 remainingDebt = 500 ether + borrowerInterest - amountLiquidated;

    //     // Exactly half of total debt is liquidated so remainingDebt == amountLiquidated
    //     assertEq(remainingDebt, 401.853426710065837121 ether);  // Rounding

    //     // Remaining debt that the user owes divided by the current cash (liquidated amount) plus the outstanding debt
    //     ( uint256 borrowRate, uint256 liquidityRate ) = _getUpdatedRates(remainingDebt, amountLiquidated + remainingDebt);

    //     assertEq(borrowRate,    0.071107949021420119560801662e27);
    //     assertEq(liquidityRate, 0.056938881872158411761847649e27);

    //     collateralReserveParams.lastUpdateTimestamp = 1 + WARP_TIME;

    //     borrowReserveParams.liquidityIndex            = expectedLiquidityIndex;
    //     borrowReserveParams.currentLiquidityRate      = liquidityRate + 2;  // Rounding
    //     borrowReserveParams.variableBorrowIndex       = expectedVariableBorrowIndex;
    //     borrowReserveParams.currentVariableBorrowRate = borrowRate + 2;  // Rounding
    //     borrowReserveParams.lastUpdateTimestamp       = 1 + WARP_TIME;

    //     aCollateralAssetParams.userBalance = 1000 ether - 101 ether;  // 1% liquidation bonus taken from borrower (rounding)
    //     aCollateralAssetParams.totalSupply = 1000 ether - 101 ether;

    //     borrowAssetDebtTokenParams.userBalance = remainingDebt;
    //     borrowAssetDebtTokenParams.totalSupply = remainingDebt;

    //     collateralAssetParams.userBalance   = 101 ether;               // 1% liquidation bonus given to liquidator (rounding)
    //     collateralAssetParams.aTokenBalance = 1000 ether - 101 ether;  // 1% liquidation bonus given to liquidator (rounding)

    //     borrowAssetParams.allowance     = 1000 ether - 100 ether;
    //     borrowAssetParams.userBalance   = 1000 ether - 100 ether;
    //     borrowAssetParams.aTokenBalance = 100 ether;

    //     _assertPoolReserveState(collateralReserveParams);
    //     _assertPoolReserveState(borrowReserveParams);

    //     _assertATokenState(aCollateralAssetParams);
    //     _assertDebtTokenState(borrowAssetDebtTokenParams);

    //     _assertAssetState(collateralAssetParams);
    //     _assertAssetState(borrowAssetParams);

    //     ( ,,,,, healthFactor ) = pool.getUserAccountData(borrower);

    //     assertEq(healthFactor, 1.118567044905117714e18);  // User position is healthy again after liquidation
    // }

    // function test_liquidationCall_09() public {
    //     skip(1000 days);

    //     vm.startPrank(liquidator);
    //     borrowAsset.mint(liquidator, 2000 ether);
    //     borrowAsset.approve(address(pool), 2000 ether);

    //     (
    //         AssertPoolReserveStateParams memory collateralReserveParams,
    //         AssertPoolReserveStateParams memory borrowReserveParams,
    //         AssertATokenStateParams      memory aCollateralAssetParams,
    //         AssertDebtTokenStateParams   memory borrowAssetDebtTokenParams,
    //         AssertAssetStateParams       memory collateralAssetParams,
    //         AssertAssetStateParams       memory borrowAssetParams,
    //         uint256 borrowerInterest,
    //         uint256 compoundedNormalizedInterest,
    //         uint256 expectedLiquidityIndex,
    //         uint256 expectedVariableBorrowIndex
    //     ) = _loadStartingParamsAndAssertState({
    //         timeSinceLastUpdate:         1000 days,
    //         borrowerCollateral:          1000 ether,
    //         borrowerInitialBorrow:       500 ether,
    //         liquidatorLiquidationAmount: 2000 ether
    //     });

    //     borrowerInterest += 2;  // Rounding

    //     assertEq(borrowerInterest, 850.548092145123279591 ether);  // Total debt > collateral (1350 > 1000)

    //     assertEq(expectedLiquidityIndex,       2.013698630136986301369863013e27);  // 1000/365 x 37%
    //     assertEq(expectedVariableBorrowIndex,  2.701096184290246559179463013e27);  // Significant difference because large APR and compounded over 2 years
    //     assertEq(compoundedNormalizedInterest, 2.701096184290246559179463013e27);

    //     ( ,,,,, uint256 healthFactor ) = pool.getUserAccountData(borrower);

    //     assertEq(healthFactor, 0.370220063180222679e18);  // Less than 0.95 so full debt position is liquidatable at once

    //     assertEq(pool.getUserConfiguration(borrower).isBorrowing(borrowAssetId),             true);
    //     assertEq(pool.getUserConfiguration(borrower).isUsingAsCollateral(collateralAssetId), true);

    //     pool.liquidationCall(address(collateralAsset), address(borrowAsset), borrower, 2000 ether, false);

    //     // Debt corresponding to the max collateral liquidated is recalculated in this case
    //     uint256 debtLiquidated = uint256(1000 ether * 100)/101 + 1;  // Rounding
    //     uint256 badDebt        = 500 ether + borrowerInterest - debtLiquidated;

    //     assertEq(debtLiquidated, 990.099009900990099010 ether);
    //     assertEq(badDebt,        360.449082244133180581 ether);  // Debt left over after all collateral is liquidated

    //     // Remaining outstanding debt that the user owes (bad debt) divided by the current cash (liquidated amount) plus the outstanding debt
    //     ( uint256 borrowRate, uint256 liquidityRate ) = _getUpdatedRates(badDebt, debtLiquidated + badDebt);

    //     // Borrow rate and liquidity rate are above base because there is still bad debt left
    //     assertEq(borrowRate,    0.056672274100058502185344186e27);
    //     assertEq(liquidityRate, 0.015125317866769464179973744e27);

    //     collateralReserveParams.lastUpdateTimestamp = 1 + 1000 days;

    //     borrowReserveParams.liquidityIndex            = expectedLiquidityIndex;
    //     borrowReserveParams.currentLiquidityRate      = liquidityRate + 1;  // Rounding
    //     borrowReserveParams.variableBorrowIndex       = expectedVariableBorrowIndex;
    //     borrowReserveParams.currentVariableBorrowRate = borrowRate + 2;  // Rounding
    //     borrowReserveParams.lastUpdateTimestamp       = 1 + 1000 days;

    //     aCollateralAssetParams.userBalance = 0;
    //     aCollateralAssetParams.totalSupply = 0;

    //     borrowAssetDebtTokenParams.userBalance = badDebt;
    //     borrowAssetDebtTokenParams.totalSupply = badDebt;

    //     collateralAssetParams.userBalance   = 1000 ether;
    //     collateralAssetParams.aTokenBalance = 0;

    //     borrowAssetParams.allowance     = 2000 ether - debtLiquidated;
    //     borrowAssetParams.userBalance   = 2000 ether - debtLiquidated;
    //     borrowAssetParams.aTokenBalance = debtLiquidated;

    //     _assertPoolReserveState(collateralReserveParams);
    //     _assertPoolReserveState(borrowReserveParams);

    //     _assertATokenState(aCollateralAssetParams);
    //     _assertDebtTokenState(borrowAssetDebtTokenParams);

    //     _assertAssetState(collateralAssetParams);
    //     _assertAssetState(borrowAssetParams);

    //     ( ,,,,, healthFactor ) = pool.getUserAccountData(borrower);

    //     assertEq(healthFactor, 0);  // User has debt but no collateral so their HF goes to zero

    //     assertEq(pool.getUserConfiguration(borrower).isBorrowing(borrowAssetId),             true);
    //     assertEq(pool.getUserConfiguration(borrower).isUsingAsCollateral(collateralAssetId), false);
    // }

    // function test_liquidationCall_10() public {
    //     skip(1000 days);

    //     vm.startPrank(liquidator);
    //     borrowAsset.mint(liquidator, 2000 ether);
    //     borrowAsset.approve(address(pool), 2000 ether);

    //     (
    //         AssertPoolReserveStateParams memory collateralReserveParams,
    //         AssertPoolReserveStateParams memory borrowReserveParams,
    //         AssertATokenStateParams      memory aCollateralAssetParams,
    //         AssertDebtTokenStateParams   memory borrowAssetDebtTokenParams,
    //         AssertAssetStateParams       memory collateralAssetParams,
    //         AssertAssetStateParams       memory borrowAssetParams,
    //         uint256 borrowerInterest,
    //         uint256 compoundedNormalizedInterest,
    //         uint256 expectedLiquidityIndex,
    //         uint256 expectedVariableBorrowIndex
    //     ) = _loadStartingParamsAndAssertState({
    //         timeSinceLastUpdate:         1000 days,
    //         borrowerCollateral:          1000 ether,
    //         borrowerInitialBorrow:       500 ether,
    //         liquidatorLiquidationAmount: 2000 ether
    //     });

    //     borrowerInterest += 2;  // Rounding

    //     assertEq(borrowerInterest, 850.548092145123279591 ether);  // Total debt > collateral (1350 > 1000)

    //     assertEq(expectedLiquidityIndex,       2.013698630136986301369863013e27);  // 1000/365 x 37%
    //     assertEq(expectedVariableBorrowIndex,  2.701096184290246559179463013e27);  // Significant difference because large APR and compounded over 2 years
    //     assertEq(compoundedNormalizedInterest, 2.701096184290246559179463013e27);

    //     ( ,,,,, uint256 healthFactor ) = pool.getUserAccountData(borrower);

    //     assertEq(healthFactor, 0.370220063180222679e18);  // Less than 0.95 so full debt position is liquidatable at once

    //     assertEq(pool.getUserConfiguration(borrower).isBorrowing(borrowAssetId),             true);
    //     assertEq(pool.getUserConfiguration(borrower).isUsingAsCollateral(collateralAssetId), true);

    //     pool.liquidationCall(address(collateralAsset), address(borrowAsset), borrower, 1200 ether, false);

    //     // Debt corresponding to the max collateral liquidated is recalculated in this case
    //     uint256 debtLiquidated = uint256(1000 ether * 100)/101 + 1;  // Rounding
    //     uint256 badDebt        = 500 ether + borrowerInterest - debtLiquidated;

    //     assertEq(debtLiquidated, 990.099009900990099010 ether);
    //     assertEq(badDebt,        360.449082244133180581 ether);  // Debt left over after all collateral is liquidated

    //     // Remaining outstanding debt that the user owes (bad debt) divided by the current cash (liquidated amount) plus the outstanding debt
    //     ( uint256 borrowRate, uint256 liquidityRate ) = _getUpdatedRates(badDebt, debtLiquidated + badDebt);

    //     // Borrow rate and liquidity rate are above base because there is still bad debt left
    //     assertEq(borrowRate,    0.056672274100058502185344186e27);
    //     assertEq(liquidityRate, 0.015125317866769464179973744e27);

    //     collateralReserveParams.lastUpdateTimestamp = 1 + 1000 days;

    //     borrowReserveParams.liquidityIndex            = expectedLiquidityIndex;
    //     borrowReserveParams.currentLiquidityRate      = liquidityRate + 1;  // Rounding
    //     borrowReserveParams.variableBorrowIndex       = expectedVariableBorrowIndex;
    //     borrowReserveParams.currentVariableBorrowRate = borrowRate + 2;  // Rounding
    //     borrowReserveParams.lastUpdateTimestamp       = 1 + 1000 days;

    //     aCollateralAssetParams.userBalance = 0;
    //     aCollateralAssetParams.totalSupply = 0;

    //     borrowAssetDebtTokenParams.userBalance = badDebt;
    //     borrowAssetDebtTokenParams.totalSupply = badDebt;

    //     collateralAssetParams.userBalance   = 1000 ether;
    //     collateralAssetParams.aTokenBalance = 0;

    //     borrowAssetParams.allowance     = 2000 ether - debtLiquidated;
    //     borrowAssetParams.userBalance   = 2000 ether - debtLiquidated;
    //     borrowAssetParams.aTokenBalance = debtLiquidated;

    //     _assertPoolReserveState(collateralReserveParams);
    //     _assertPoolReserveState(borrowReserveParams);

    //     _assertATokenState(aCollateralAssetParams);
    //     _assertDebtTokenState(borrowAssetDebtTokenParams);

    //     _assertAssetState(collateralAssetParams);
    //     _assertAssetState(borrowAssetParams);

    //     ( ,,,,, healthFactor ) = pool.getUserAccountData(borrower);

    //     assertEq(healthFactor, 0);  // User has debt but no collateral so their HF goes to zero

    //     assertEq(pool.getUserConfiguration(borrower).isBorrowing(borrowAssetId),             true);
    //     assertEq(pool.getUserConfiguration(borrower).isUsingAsCollateral(collateralAssetId), false);
    // }

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
            State memory state,
            uint256 borrowerInterest,
            uint256 compoundedNormalizedInterest,
            uint256 expectedLiquidityIndex,
            uint256 expectedVariableBorrowIndex
        )
    {
        state.collateralReserveParams = AssertPoolReserveStateParams({
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

        state.borrowReserveParams = AssertPoolReserveStateParams({
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

        state.aCollateralAssetParams = AssertATokenStateParams({
            user:        borrower,
            aToken:      address(aCollateralAsset),
            userBalance: borrowerCollateral,
            totalSupply: borrowerCollateral
        });

        compoundedNormalizedInterest = _getCompoundedNormalizedInterest(0.37e27, timeSinceLastUpdate);

        borrowerInterest = (compoundedNormalizedInterest - 1e27) * borrowerInitialBorrow / 1e27;

        expectedLiquidityIndex      = 1e27 + (1e27 * 0.37e27 * timeSinceLastUpdate / 365 days / 1e27);
        expectedVariableBorrowIndex = 1e27 * compoundedNormalizedInterest / 1e27;

        state.borrowAssetDebtTokenParams = AssertDebtTokenStateParams({
            user:        borrower,
            debtToken:   debtToken,
            userBalance: borrowerInitialBorrow + borrowerInterest,
            totalSupply: borrowerInitialBorrow + borrowerInterest
        });

        state.collateralAssetParams = AssertAssetStateParams({
            user:          liquidator,
            asset:         address(collateralAsset),
            allowance:     0,
            userBalance:   0,
            aTokenBalance: borrowerCollateral
        });

        state.borrowAssetParams = AssertAssetStateParams({
            user:          liquidator,
            asset:         address(borrowAsset),
            allowance:     liquidatorLiquidationAmount,
            userBalance:   liquidatorLiquidationAmount,
            aTokenBalance: 0
        });

        _assertPoolReserveState(state.collateralReserveParams);
        _assertPoolReserveState(state.borrowReserveParams);

        _assertATokenState(state.aCollateralAssetParams);
        _assertDebtTokenState({ params: state.borrowAssetDebtTokenParams, tolerance: 1 });  // Allow rounding because of interest calculation

        _assertAssetState(state.collateralAssetParams);
        _assertAssetState(state.borrowAssetParams);
    }

}
