// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { ReserveConfiguration } from "aave-v3-core/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import { UserConfiguration }    from "aave-v3-core/contracts/protocol/libraries/configuration/UserConfiguration.sol";
import { Errors }               from "aave-v3-core/contracts/protocol/libraries/helpers/Errors.sol";
import { DataTypes }            from "aave-v3-core/contracts/protocol/libraries/types/DataTypes.sol";

import { MockOracleSentinel } from "test/mocks/MockOracleSentinel.sol";
import { MockOracle }         from "test/mocks/MockOracle.sol";

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

    /**********************************************************************************************/
    /*** Modifiers                                                                              ***/
    /**********************************************************************************************/

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

    modifier whenAmountLtAvailableDebt { _; }

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

    modifier whenUserIsInEmode {
        address oracle = aaveOracle.getSourceOfAsset(address(collateralAsset));

        // Update the price of the collateralAsset to demo price override
        // Since rest of tests use 1:1 and emode uses 1:1, 1.01:1 is used for non override case
        MockOracle(oracle).__setPrice(1.01e8);

        vm.startPrank(admin);
        poolConfigurator.setEModeCategory({
            categoryId:           1,
            ltv:                  60_00,
            liquidationThreshold: 60_00,
            liquidationBonus:     105_00,
            oracle:               address(0),
            label:                "emode1"
        });

        poolConfigurator.setAssetEModeCategory(address(collateralAsset), 1);
        poolConfigurator.setAssetEModeCategory(address(borrowAsset),     1);

        vm.stopPrank();

        vm.prank(borrower);
        pool.setUserEMode(1);

        _;
    }

    modifier whenEmodePriceSourceIsOverridden {
        address emodePriceSourceAsset = makeAddr("emodePriceSourceAsset");

        // Price is $2
        _setUpMockOracle(emodePriceSourceAsset, 1e8);

        // Update to change the price source only
        // NOTE: This is not an oracle directly, but an asset that the AAVE oracle uses
        vm.startPrank(admin);
        poolConfigurator.setEModeCategory({
            categoryId:           1,
            ltv:                  60_00,
            liquidationThreshold: 60_00,
            liquidationBonus:     105_00,
            oracle:               emodePriceSourceAsset,
            label:                "emode1"
        });

        _;
    }

    modifier whenEmodePriceSourceIsNotOverridden { _; }

    modifier whenLiquidatorSelectsReceiveAToken {
        _;

        assertGt(aCollateralAsset.balanceOf(liquidator), 0);
    }

    modifier whenLiquidatorHasNoAToken { _; }

    modifier whenValidateAutomaticUseOfCollateralIsFalse {
        address newAsset = _setUpNewCollateral();

        vm.prank(admin);
        poolConfigurator.setDebtCeiling(address(newAsset), 1000);

        _supplyAndUseAsCollateral(liquidator, address(newAsset), 500 ether);

        _;
    }

    modifier whenValidateAutomaticUseOfCollateralIsTrue {
        _;
    }

    modifier whenLiquidatorHasSomeAToken {
        _supplyAndUseAsCollateral(liquidator, address(collateralAsset), 500 ether);
        _;
    }

    modifier whenUserIsInIsolationMode {
        _repay(borrower, address(borrowAsset), 500 ether);
        _withdraw(borrower, address(collateralAsset), 1000 ether);

        vm.startPrank(admin);
        poolConfigurator.setDebtCeiling(address(collateralAsset), 1000_00);
        poolConfigurator.setBorrowableInIsolation(address(borrowAsset), true);
        vm.stopPrank();

        _supplyAndUseAsCollateral(borrower, address(collateralAsset), 1000 ether);

        _borrow(borrower, address(borrowAsset), 500 ether);

        _;
    }

    /**********************************************************************************************/
    /*** Tests                                                                                  ***/
    /**********************************************************************************************/

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

        params.liquidationAmount = 800 ether;
        params.receiveAToken     = false;

        params.borrowerDebt         = 723.445957199470228858 ether; // 500 ether + 37% APR over 365 days
        params.debtLiquidated       = 723.445957199470228858 ether;
        params.collateralLiquidated = 730.680416771464931147 ether;
        params.remainingDebt        = 0;
        params.healthFactor         = type(uint256).max;  // User has no more debt

        params.liquidityIndex         = 1.37e27;                        // Full utilization for a full year
        params.borrowIndex            = 1.446891914398940457716504e27;  // Significant difference because large APR and compounded over a year
        params.resultingBorrowRate    = 0.05e27;                        // All debt removed so back to base rate
        params.resultingLiquidityRate = 0;
        params.updateTimestamp        = 1 + 365 days;

        params.isBorrowing         = false;
        params.isUsingAsCollateral = true;

        // 1% liquidation bonus goes to the liquidator (rounding)
        assertApproxEqAbs(params.collateralLiquidated, params.debtLiquidated * 101/100, 1);

        _runLiquidationTest(params);
    }

    function test_liquidationCall_02()
        public
        whenProtocolFeeIsZero
        whenUserHealthFactorBelowCloseFactorThreshold
        whenAmountLtAvailableDebt
        whenUserDebtGtCollateral
    {
        Params memory params;

        params.startingCollateral = 1000 ether;
        params.startingBorrow     = 500 ether;

        params.liquidationAmount = 1200 ether;
        params.receiveAToken     = false;

        params.borrowerDebt         = 1350.548092145123279590 ether; // Total debt > collateral (1350 > 1000)
        params.debtLiquidated       = 990.099009900990099010 ether;  // 1% liquidation bonus has to be reduced from debt side when liquidating all collateral
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

        // 1% liquidation bonus goes to the liquidator (rounding)
        assertApproxEqAbs(params.debtLiquidated, uint256(params.collateralLiquidated * 100)/101, 1);

        assertApproxEqAbs(params.remainingDebt, params.borrowerDebt - params.debtLiquidated, 1);

        _runLiquidationTest(params);
    }

    function test_liquidationCall_03()
        public
        whenProtocolFeeIsZero
        whenUserHealthFactorBelowCloseFactorThreshold
        whenAmountLtAvailableDebt
        whenUserDebtLtCollateral
    {
        Params memory params;

        params.startingCollateral = 1000 ether;
        params.startingBorrow     = 500 ether;

        params.liquidationAmount = 400 ether;
        params.receiveAToken     = false;

        params.borrowerDebt         = 723.445957199470228858 ether; // 500 ether + 37% APR over 365 days
        params.debtLiquidated       = 400 ether;
        params.collateralLiquidated = 404 ether;  // 1% liquidation bonus
        params.remainingDebt        = 323.445957199470228858 ether;
        params.healthFactor         = 0.921328566258590063e18;  // User position is still unhealthy

        params.liquidityIndex         = 1.37e27;  // Full utilization for a full year
        params.borrowIndex            = 1.446891914398940457716504e27;  // Significant difference because large APR and compounded over a year
        params.resultingBorrowRate    = 0.061177267423387126110513189e27;
        params.resultingLiquidityRate = 0.027351787128930695623282915e27;
        params.updateTimestamp        = 1 + 365 days;

        params.isBorrowing         = true;
        params.isUsingAsCollateral = true;

        // 1% liquidation bonus goes to the liquidator (rounding)
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

        params.liquidationAmount = 300 ether;  // Just above available debt (half)
        params.receiveAToken     = false;

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

        // 1% liquidation bonus goes to the liquidator (rounding)
        assertApproxEqAbs(params.collateralLiquidated, params.debtLiquidated * 101/100, 1);

        // Half of debt is liquidated when HF is above close factor threshold (0.95)
        assertApproxEqAbs(params.remainingDebt, params.borrowerDebt / 2, 1);

        _runLiquidationTest(params);
    }

    function test_liquidationCall_05()
        public
        whenProtocolFeeIsZero
        whenUserHFAboveCloseFactorThreshold
        whenAmountLtAvailableDebt
    {
        Params memory params;

        params.startingCollateral = 1000 ether;
        params.startingBorrow     = 500 ether;

        params.liquidationAmount = 200 ether;  // Just below available debt (half)
        params.receiveAToken     = false;

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

        // 1% liquidation bonus goes to the liquidator (rounding)
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

        params.liquidationAmount = 800 ether;
        params.receiveAToken     = false;

        params.borrowerDebt         = 723.445957199470228858 ether; // 500 ether + 37% APR over 365 days
        params.debtLiquidated       = 723.445957199470228858 ether;
        params.collateralLiquidated = 730.680416771464931147 ether;
        params.protocolFee          = 1.446891914398940458 ether;
        params.remainingDebt        = 0;
        params.healthFactor         = type(uint256).max;  // User has no more debt

        params.liquidityIndex         = 1.37e27;                        // Full utilization for a full year
        params.borrowIndex            = 1.446891914398940457716504e27;  // Significant difference because large APR and compounded over a year
        params.resultingBorrowRate    = 0.05e27;                        // All debt removed so back to base rate
        params.resultingLiquidityRate = 0;
        params.updateTimestamp        = 1 + 365 days;

        params.isBorrowing         = false;
        params.isUsingAsCollateral = true;

        // 1% liquidation bonus goes to the liquidator (rounding)
        assertApproxEqAbs(params.collateralLiquidated, params.debtLiquidated * 101/100, 1);

        // Protocol fee is 20% of the bonus collateral amount (below calc uses 1:1 pricing)
        assertApproxEqAbs(params.protocolFee, (params.collateralLiquidated - params.debtLiquidated) * 20/100, 1);

        _runLiquidationTest(params);
    }

    function test_liquidationCall_07()
        public
        whenProtocolFeeIsNotZero
        whenUserHealthFactorBelowCloseFactorThreshold
        whenAmountLtAvailableDebt
        whenUserDebtGtCollateral
    {
        Params memory params;

        params.startingCollateral = 1000 ether;
        params.startingBorrow     = 500 ether;

        params.liquidationAmount = 1200 ether;
        params.receiveAToken     = false;

        params.borrowerDebt         = 1350.548092145123279590 ether; // Total debt > collateral (1350 > 1000)
        params.debtLiquidated       = 990.099009900990099010 ether;  // 1% liquidation bonus has to be reduced from debt side when liquidating all collateral
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

        // 1% liquidation bonus goes to the liquidator (rounding)
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
        whenAmountLtAvailableDebt
        whenUserDebtLtCollateral
    {
        Params memory params;

        params.startingCollateral = 1000 ether;
        params.startingBorrow     = 500 ether;

        params.liquidationAmount = 400 ether;
        params.receiveAToken     = false;

        params.borrowerDebt         = 723.445957199470228858 ether; // 500 ether + 37% APR over 365 days
        params.debtLiquidated       = 400 ether;
        params.collateralLiquidated = 404 ether;  // 1% liquidation bonus
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

        // 1% liquidation bonus goes to the liquidator (rounding)
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

        params.liquidationAmount = 300 ether;  // Just above available debt (half)
        params.receiveAToken     = false;

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

        // 1% liquidation bonus goes to the liquidator (rounding)
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
        whenAmountLtAvailableDebt
    {
        Params memory params;

        params.startingCollateral = 1000 ether;
        params.startingBorrow     = 500 ether;

        params.liquidationAmount = 200 ether;  // Just below available debt (half)
        params.receiveAToken     = false;

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

        // 1% liquidation bonus goes to the liquidator (rounding)
        assertApproxEqAbs(params.collateralLiquidated, params.debtLiquidated * 101/100, 1);

        // Protocol fee is 20% of the bonus collateral amount (below calc uses 1:1 pricing)
        assertApproxEqAbs(params.protocolFee, (params.collateralLiquidated - params.debtLiquidated) * 20/100, 1);

        // Specified debt is liquidated
        assertApproxEqAbs(params.remainingDebt, params.borrowerDebt - 200 ether, 1);

        _runLiquidationTest(params);
    }

    // NOTE: Using the whenProtocolFeeIsNotZero to give a better test even though not in tree
    function test_liquidationCall_11()
        public
        whenProtocolFeeIsNotZero
        whenUserIsInEmode
        whenEmodePriceSourceIsOverridden
    {
        skip(365 days);

        Params memory params;

        params.startingCollateral = 1000 ether;
        params.startingBorrow     = 500 ether;

        params.liquidationAmount = 600 ether;
        params.receiveAToken     = false;

        params.borrowerDebt         = 723.445957199470228858 ether;  // 500 ether + 37% APR over 365 days
        params.debtLiquidated       = 600 ether;
        params.collateralLiquidated = 630 ether;  // 5% liquidation bonus
        params.protocolFee          = 6 ether;
        params.remainingDebt        = 123.445957199470228859 ether;
        params.healthFactor         = 1.798357800072075410e18;

        params.liquidityIndex         = 1.37e27;  // Full utilization for a full year
        params.borrowIndex            = 1.446891914398940457716504e27;  // Significant difference because large APR and compounded over a year
        params.resultingBorrowRate    = 0.054265901135080689165798444e27;  // All debt removed so back to base rate
        params.resultingLiquidityRate = 0.009259718769932686820914091e27;
        params.updateTimestamp        = 1 + 365 days;

        params.isBorrowing         = true;
        params.isUsingAsCollateral = true;

        // 5% liquidation bonus goes to the liquidator (rounding)
        assertApproxEqAbs(params.collateralLiquidated, params.debtLiquidated * 105/100, 1);

        // Protocol fee is 20% of the bonus collateral amount (below calc uses 1.01:1 pricing)
        assertApproxEqAbs(params.protocolFee, (params.collateralLiquidated - params.debtLiquidated) * 20/100, 1);

        _runLiquidationTest(params);
    }

    function test_liquidationCall_12()
        public
        whenProtocolFeeIsNotZero
        whenUserIsInEmode
        whenEmodePriceSourceIsNotOverridden
    {
        skip(365 days);

        Params memory params;

        params.startingCollateral = 1000 ether;
        params.startingBorrow     = 500 ether;

        params.liquidationAmount = 600 ether;
        params.receiveAToken     = false;

        params.borrowerDebt         = 723.445957199470228858 ether;  // 500 ether + 37% APR over 365 days
        params.debtLiquidated       = 600 ether;
        params.collateralLiquidated = 623.762376237623762375 ether;  // 5% liquidation bonus
        params.protocolFee          = 5.940594059405940594 ether;
        params.remainingDebt        = 123.445957199470228859 ether;
        params.healthFactor         = 1.846962064938888259e18;

        params.liquidityIndex         = 1.37e27;  // Full utilization for a full year
        params.borrowIndex            = 1.446891914398940457716504e27;  // Significant difference because large APR and compounded over a year
        params.resultingBorrowRate    = 0.054265901135080689165798444e27;  // All debt removed so back to base rate
        params.resultingLiquidityRate = 0.009259718769932686820914091e27;
        params.updateTimestamp        = 1 + 365 days;

        params.isBorrowing         = true;
        params.isUsingAsCollateral = true;

        // 5% liquidation bonus goes to the liquidator using a 1.01 price (rounding)
        assertApproxEqAbs(params.collateralLiquidated, params.debtLiquidated * 105/100 * 100/101, 1);

        // Protocol fee is 20% of the bonus collateral amount (below calc uses 1.01:1 pricing)
        assertApproxEqAbs(params.protocolFee, (params.collateralLiquidated - params.debtLiquidated * 100/101) * 20/100, 1);

        _runLiquidationTest(params);
    }

    // NOTE: Using the whenProtocolFeeIsNotZero to give a better test even though not in tree
    function test_liquidationCall_13()
        public
        whenProtocolFeeIsNotZero
        whenLiquidatorSelectsReceiveAToken
        whenLiquidatorHasNoAToken
        whenValidateAutomaticUseOfCollateralIsFalse
    {
        skip(365 days);

        Params memory params;

        params.startingCollateral = 1000 ether;
        params.startingBorrow     = 500 ether;

        params.liquidationAmount = 600 ether;
        params.receiveAToken     = true;

        params.borrowerDebt         = 723.445957199470228858 ether;  // 500 ether + 37% APR over 365 days
        params.debtLiquidated       = 600 ether;
        params.collateralLiquidated = 606 ether;  // 1% liquidation bonus
        params.protocolFee          = 1.2 ether;
        params.remainingDebt        = 123.445957199470228859 ether;
        params.healthFactor         = 1.595840029793688540e18;

        params.liquidityIndex         = 1.37e27;  // Full utilization for a full year
        params.borrowIndex            = 1.446891914398940457716504e27;  // Significant difference because large APR and compounded over a year
        params.resultingBorrowRate    = 0.054265901135080689165798444e27;  // All debt removed so back to base rate
        params.resultingLiquidityRate = 0.009259718769932686820914091e27;
        params.updateTimestamp        = 1 + 365 days;

        params.isBorrowing         = true;
        params.isUsingAsCollateral = true;

        // 1% liquidation bonus goes to the liquidator (rounding)
        assertApproxEqAbs(params.collateralLiquidated, params.debtLiquidated * 101/100, 1);

        // Protocol fee is 20% of the bonus collateral amount (below calc uses 1:1 pricing)
        assertApproxEqAbs(params.protocolFee, (params.collateralLiquidated - params.debtLiquidated) * 20/100, 1);

        _runLiquidationTest(params);

        assertEq(
            pool.getUserConfiguration(liquidator).isUsingAsCollateral(collateralAssetId),
            false,
            "liquidator.isUsingAsCollateral"
        );
    }

    function test_liquidationCall_14()
        public
        whenProtocolFeeIsNotZero
        whenLiquidatorSelectsReceiveAToken
        whenLiquidatorHasNoAToken
        whenValidateAutomaticUseOfCollateralIsTrue
    {
        skip(365 days);

        Params memory params;

        params.startingCollateral = 1000 ether;
        params.startingBorrow     = 500 ether;

        params.liquidationAmount = 600 ether;
        params.receiveAToken     = true;

        params.borrowerDebt         = 723.445957199470228858 ether;  // 500 ether + 37% APR over 365 days
        params.debtLiquidated       = 600 ether;
        params.collateralLiquidated = 606 ether;  // 1% liquidation bonus
        params.protocolFee          = 1.2 ether;
        params.remainingDebt        = 123.445957199470228859 ether;
        params.healthFactor         = 1.595840029793688540e18;

        params.liquidityIndex         = 1.37e27;  // Full utilization for a full year
        params.borrowIndex            = 1.446891914398940457716504e27;  // Significant difference because large APR and compounded over a year
        params.resultingBorrowRate    = 0.054265901135080689165798444e27;  // All debt removed so back to base rate
        params.resultingLiquidityRate = 0.009259718769932686820914091e27;
        params.updateTimestamp        = 1 + 365 days;

        params.isBorrowing         = true;
        params.isUsingAsCollateral = true;

        // 1% liquidation bonus goes to the liquidator (rounding)
        assertApproxEqAbs(params.collateralLiquidated, params.debtLiquidated * 101/100, 1);

        // Protocol fee is 20% of the bonus collateral amount (below calc uses 1:1 pricing)
        assertApproxEqAbs(params.protocolFee, (params.collateralLiquidated - params.debtLiquidated) * 20/100, 1);

        _runLiquidationTest(params);

        assertEq(
            pool.getUserConfiguration(liquidator).isUsingAsCollateral(collateralAssetId),
            true,
            "liquidator.isUsingAsCollateral"
        );
    }

    // NOTE: whenLiquidatorHasSomeAToken breaks assertion logic in helper so just focusing on isUsingAsCollateral change
    function test_liquidationCall_15()
        public
        whenProtocolFeeIsNotZero
        whenLiquidatorSelectsReceiveAToken
        whenLiquidatorHasSomeAToken
    {
        skip(365 days);

        assertEq(
            pool.getUserConfiguration(liquidator).isUsingAsCollateral(collateralAssetId),
            true,
            "liquidator.isUsingAsCollateral.before"
        );

        vm.startPrank(liquidator);
        borrowAsset.mint(liquidator, 1000 ether);
        borrowAsset.approve(address(pool), 1000 ether);
        pool.liquidationCall(
            address(collateralAsset),
            address(borrowAsset),
            borrower,
            1000 ether,
            true
        );

        assertEq(
            pool.getUserConfiguration(liquidator).isUsingAsCollateral(collateralAssetId),
            true,
            "liquidator.isUsingAsCollateral.after"
        );
    }

    function test_liquidationCall_16()
        public
        whenProtocolFeeIsNotZero
        whenUserIsInIsolationMode
    {
        skip(365 days);

        Params memory params;

        params.startingCollateral = 1000 ether;
        params.startingBorrow     = 500 ether;

        params.liquidationAmount = 600 ether;
        params.receiveAToken     = true;

        params.borrowerDebt         = 723.445957199470228858 ether;  // 500 ether + 37% APR over 365 days
        params.debtLiquidated       = 600 ether;
        params.collateralLiquidated = 606 ether;  // 1% liquidation bonus
        params.protocolFee          = 1.2 ether;
        params.remainingDebt        = 123.445957199470228859 ether;
        params.healthFactor         = 1.595840029793688540e18;

        params.liquidityIndex         = 1.37e27;  // Full utilization for a full year
        params.borrowIndex            = 1.446891914398940457716504e27;     // Significant difference because large APR and compounded over a year
        params.resultingBorrowRate    = 0.054265901135080689165798444e27;  // All debt removed so back to base rate
        params.resultingLiquidityRate = 0.009259718769932686820914091e27;
        params.updateTimestamp        = 1 + 365 days;

        params.isBorrowing         = true;
        params.isUsingAsCollateral = true;

        // 1% liquidation bonus goes to the liquidator (rounding)
        assertApproxEqAbs(params.collateralLiquidated, params.debtLiquidated * 101/100, 1);

        // Protocol fee is 20% of the bonus collateral amount (below calc uses 1:1 pricing)
        assertApproxEqAbs(params.protocolFee, (params.collateralLiquidated - params.debtLiquidated) * 20/100, 1);

        assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 500_00);

        _runLiquidationTest(params);

        // NOTE: Iso mode doesn't update the total debt before reducing it so it's doing 500 - 600 here and preventing underflow
        assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);
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

    struct Params {
        uint256 startingCollateral;
        uint256 startingBorrow;
        uint256 liquidationAmount;
        bool    receiveAToken;
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
            params.receiveAToken
        );

        // Remaining outstanding debt that the user owes divided by the current cash (liquidated amount) plus the outstanding debt
        ( uint256 borrowRate, uint256 liquidityRate )
            = _getUpdatedRates(params.remainingDebt, params.debtLiquidated + params.remainingDebt);

        // Calculated values and expected values are within 2e-27 of each other
        assertApproxEqAbs(borrowRate,    params.resultingBorrowRate,    2, "borrowRate");
        assertApproxEqAbs(liquidityRate, params.resultingLiquidityRate, 2, "liquidityRate");

        state.borrowReserveParams.liquidityIndex            = params.liquidityIndex;
        state.borrowReserveParams.currentLiquidityRate      = params.resultingLiquidityRate;
        state.borrowReserveParams.variableBorrowIndex       = params.borrowIndex;
        state.borrowReserveParams.currentVariableBorrowRate = params.resultingBorrowRate;
        state.borrowReserveParams.lastUpdateTimestamp       = params.updateTimestamp;

        state.borrowAssetDebtTokenParams.userBalance = params.remainingDebt;
        state.borrowAssetDebtTokenParams.totalSupply = params.remainingDebt;

        state.borrowAssetParams.allowance     = params.liquidationAmount - params.debtLiquidated;
        state.borrowAssetParams.userBalance   = params.liquidationAmount - params.debtLiquidated;
        state.borrowAssetParams.aTokenBalance = params.debtLiquidated;

        // The borrower's aToken balance is always reduced by the collateralLiquidated amount, and treasury gets protocolFee aTokens
        // When receiveAToken is true, collateralLiquidated aTokens are transferred to the liquidator and protocolFee aTokens are transferred to the protocol
        // When receiveAToken is false:
        //   - collateralLiquidated aTokens are burned for the underlying
        //   - protocolFee collateralAsset are transferred to aCollateralAsset and the corresponding amount of aCollateral tokens are minted to the treasury
        //   - The collateral reserve state is updated to reflect the new aToken balance
        //   - collateralLiquidated collateralAsset is transferred to the liquidator

        state.aCollateralAssetParams.userBalance = params.startingCollateral - params.collateralLiquidated;

        assertEq(aCollateralAsset.balanceOf(treasury), params.protocolFee, "protocolFee");

        if (params.receiveAToken) {
            assertEq(aCollateralAsset.balanceOf(liquidator), params.collateralLiquidated - params.protocolFee, "aToken.liquidatorBalance");
        } else {
            state.aCollateralAssetParams.totalSupply = params.startingCollateral - params.collateralLiquidated + params.protocolFee;

            state.collateralAssetParams.userBalance   = params.collateralLiquidated - params.protocolFee;
            state.collateralAssetParams.aTokenBalance = params.startingCollateral - params.collateralLiquidated + params.protocolFee;

            state.collateralReserveParams.lastUpdateTimestamp = params.updateTimestamp;
        }

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

}
