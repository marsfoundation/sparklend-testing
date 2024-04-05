// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { Errors } from "sparklend-v1-core/contracts/protocol/libraries/helpers/Errors.sol";

import { SparkLendTestBase } from "./SparkLendTestBase.sol";

contract RepayWithATokensTestBase is SparkLendTestBase {

    address borrower = makeAddr("borrower");
    address lender   = makeAddr("lender");

    function setUp() public virtual override {
        super.setUp();

        vm.label(borrower, "borrower");

        _initCollateral({
            asset:                address(collateralAsset),
            ltv:                  5000,
            liquidationThreshold: 5000,
            liquidationBonus:     100_01
        });

        vm.prank(admin);
        poolConfigurator.setReserveBorrowing(address(borrowAsset), true);

        _supplyAndUseAsCollateral(borrower, address(collateralAsset), 1000 ether);
        _supply(borrower, address(borrowAsset), 500 ether);  // Supply to get aTokens
        _borrow(borrower, address(borrowAsset), 500 ether);
    }

}

contract RepayWithATokensFailureTests is RepayWithATokensTestBase {

    function test_repayWithATokens_whenAmountZero() public virtual {
        vm.expectRevert(bytes(Errors.INVALID_AMOUNT));
        pool.repayWithATokens(address(borrowAsset), 0, 2);
    }

    function test_repayWithATokens_whenNotActive() public virtual {
        _repay(borrower, address(borrowAsset), 500 ether);
        _withdraw(borrower, address(borrowAsset), 500 ether);

        vm.prank(admin);
        poolConfigurator.setReserveActive(address(borrowAsset), false);

        vm.expectRevert(bytes(Errors.RESERVE_INACTIVE));
        pool.repayWithATokens(address(borrowAsset), 500 ether, 2);
    }

    function test_repayWithATokens_whenPaused() public {
        vm.prank(admin);
        poolConfigurator.setReservePause(address(borrowAsset), true);

        vm.expectRevert(bytes(Errors.RESERVE_PAUSED));
        pool.repayWithATokens(address(borrowAsset), 500 ether, 2);
    }

    function test_repayWithATokens_success_whenFrozen() public {
        vm.prank(admin);
        poolConfigurator.setReserveFreeze(address(borrowAsset), true);

        vm.prank(borrower);
        pool.repayWithATokens(address(borrowAsset), 500 ether, 2);
    }

    function test_repayWithATokens_noDebt() public virtual {
        vm.expectRevert(bytes(Errors.NO_DEBT_OF_SELECTED_TYPE));
        pool.repayWithATokens(address(borrowAsset), 500 ether, 2);
    }

}

// contract RepayWithATokensConcreteTests is RepayWithATokensTestBase {

//     address debtToken;

//     function setUp() public virtual override {
//         super.setUp();
//         debtToken = pool.getReserveData(address(borrowAsset)).variableDebtTokenAddress;
//     }

//     modifier givenNoTimeHasPassedSinceBorrow { _; }

//     modifier givenSomeTimeHasPassedSinceBorrow() {
//         skip(WARP_TIME);
//         _;
//     }

//     modifier givenNotInIsolationMode { _; }

//     modifier givenInIsolationMode {
//         // Remove liquidity so initial DC can be set
//         _repay(borrower, address(borrowAsset), 500 ether);
//         _withdraw(borrower, address(collateralAsset), 1000 ether);

//         vm.startPrank(admin);
//         poolConfigurator.setBorrowableInIsolation(address(borrowAsset), true);
//         poolConfigurator.setDebtCeiling(address(collateralAsset), 1000_00);
//         vm.stopPrank();

//         _supplyAndUseAsCollateral(borrower, address(collateralAsset), 1000 ether);  // Don't have to useAsCollateral again
//         _borrow(borrower, address(borrowAsset), 500 ether);
//         _;
//     }

//     function test_repayWithATokens_01()
//         givenNotInIsolationMode
//         givenNoTimeHasPassedSinceBorrow
//         public
//     {
//         assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);

//         _repayMoreThanDebtNoTimePassedTest();

//         assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);
//     }

//     function test_repayWithATokens_02()
//         givenNotInIsolationMode
//         givenNoTimeHasPassedSinceBorrow
//         public
//     {
//         assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);

//         _repayEqualToDebtNoTimePassedTest();

//         assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);
//     }

//     function test_repayWithATokens_03()
//         givenNotInIsolationMode
//         givenNoTimeHasPassedSinceBorrow
//         public
//     {
//         assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);

//         _repayLessThanDebtNoTimePassedTest();

//         assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);
//     }

//     function test_repayWithATokens_04()
//         givenNotInIsolationMode
//         givenSomeTimeHasPassedSinceBorrow
//         public
//     {
//         assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);

//         _repayMoreThanDebtSomeTimePassedTest();

//         assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);
//     }

//     function test_repayWithATokens_05()
//         givenNotInIsolationMode
//         givenSomeTimeHasPassedSinceBorrow
//         public
//     {
//         assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);

//         _repayEqualToDebtSomeTimePassedTest();

//         assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);
//     }

//     function test_repayWithATokens_06()
//         givenNotInIsolationMode
//         givenSomeTimeHasPassedSinceBorrow
//         public
//     {
//         assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);

//         _repayLessThanDebtSomeTimePassedTest();

//         assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);
//     }

//     function test_repayWithATokens_07()
//         givenInIsolationMode
//         givenNoTimeHasPassedSinceBorrow
//         public
//     {
//         assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 500_00);

//         _repayMoreThanDebtNoTimePassedTest();

//         assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);
//     }

//     function test_repayWithATokens_08()
//         givenInIsolationMode
//         givenNoTimeHasPassedSinceBorrow
//         public
//     {
//         assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 500_00);

//         _repayEqualToDebtNoTimePassedTest();

//         assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);
//     }

//     function test_repayWithATokens_09()
//         givenInIsolationMode
//         givenNoTimeHasPassedSinceBorrow
//         public
//     {
//         assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 500_00);

//         _repayLessThanDebtNoTimePassedTest();

//         // NOTE: Repaid 500 ether - 1, but since repaid debt is rounded down, the
//         //       isolationModeTotalDebt is 0.01 ether.
//         assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 1);
//     }

//     function test_repayWithATokens_10()
//         givenInIsolationMode
//         givenSomeTimeHasPassedSinceBorrow
//         public
//     {
//         assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 500_00);

//         _repayMoreThanDebtSomeTimePassedTest();

//         assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);
//     }

//     function test_repayWithATokens_11()
//         givenInIsolationMode
//         givenSomeTimeHasPassedSinceBorrow
//         public
//     {
//         assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 500_00);

//         _repayEqualToDebtSomeTimePassedTest();

//         assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);
//     }

//     function test_repayWithATokens_12()
//         givenInIsolationMode
//         givenSomeTimeHasPassedSinceBorrow
//         public
//     {
//         assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 500_00);

//         _repayLessThanDebtSomeTimePassedTest();

//         // NOTE: When a user repays iso debt and debt has accrued, meaning there is more debt
//         //       than whats saved in storage, they can pay back the debt between the original
//         //       and the current amount, and the debt will be overwritten to zero. In this example
//         //       it's paying back 501.85 of iso debt when there is 500 in storage.
//         assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);
//     }

//     /**********************************************************************************************/
//     /*** Test running functions                                                                 ***/
//     /**********************************************************************************************/

//     function _repayMoreThanDebtNoTimePassedTest() internal {
//         borrowAsset.mint(borrower, 1);

//         AssertPoolReserveStateParams memory poolParams = AssertPoolReserveStateParams({
//             asset:                     address(borrowAsset),
//             liquidityIndex:            1e27,
//             currentLiquidityRate:      0.37e27,  // Fully utilized
//             variableBorrowIndex:       1e27,
//             currentVariableBorrowRate: 0.37e27,  // Fully utilized: 5% + 2% + 30%
//             currentStableBorrowRate:   0,
//             lastUpdateTimestamp:       1,
//             accruedToTreasury:         0,
//             unbacked:                  0
//         });

//         AssertDebtTokenStateParams memory debtTokenParams = AssertDebtTokenStateParams({
//             user:        borrower,
//             debtToken:   debtToken,
//             userBalance: 500 ether,
//             totalSupply: 500 ether
//         });

//         AssertAssetStateParams memory assetParams = AssertAssetStateParams({
//             user:          borrower,
//             asset:         address(borrowAsset),
//             allowance:     500 ether + 1,
//             userBalance:   500 ether + 1,
//             aTokenBalance: 0
//         });

//         _assertPoolReserveState(poolParams);
//         _assertDebtTokenState(debtTokenParams);
//         _assertAssetState(assetParams);

//         pool.repayWithATokens(address(borrowAsset), 500 ether + 1, 2);

//         poolParams.currentLiquidityRate      = 0;
//         poolParams.currentVariableBorrowRate = 0.05e27;

//         debtTokenParams.userBalance = 0;
//         debtTokenParams.totalSupply = 0;

//         assetParams.allowance     = 1;  // Didn't use whole allowance
//         assetParams.userBalance   = 1;  // Paid back full debt, has remaining balance
//         assetParams.aTokenBalance = 500 ether;

//         _assertPoolReserveState(poolParams);
//         _assertDebtTokenState(debtTokenParams);
//         _assertAssetState(assetParams);
//     }

//     function _repayEqualToDebtNoTimePassedTest() internal {
//         AssertPoolReserveStateParams memory poolParams = AssertPoolReserveStateParams({
//             asset:                     address(borrowAsset),
//             liquidityIndex:            1e27,
//             currentLiquidityRate:      0.37e27,  // Fully utilized
//             variableBorrowIndex:       1e27,
//             currentVariableBorrowRate: 0.37e27,  // Fully utilized: 5% + 2% + 30%
//             currentStableBorrowRate:   0,
//             lastUpdateTimestamp:       1,
//             accruedToTreasury:         0,
//             unbacked:                  0
//         });

//         AssertDebtTokenStateParams memory debtTokenParams = AssertDebtTokenStateParams({
//             user:        borrower,
//             debtToken:   debtToken,
//             userBalance: 500 ether,
//             totalSupply: 500 ether
//         });

//         AssertAssetStateParams memory assetParams = AssertAssetStateParams({
//             user:          borrower,
//             asset:         address(borrowAsset),
//             allowance:     500 ether,
//             userBalance:   500 ether,
//             aTokenBalance: 0
//         });

//         _assertPoolReserveState(poolParams);
//         _assertDebtTokenState(debtTokenParams);
//         _assertAssetState(assetParams);

//         pool.repayWithATokens(address(borrowAsset), 500 ether, 2);

//         poolParams.currentLiquidityRate      = 0;
//         poolParams.currentVariableBorrowRate = 0.05e27;

//         debtTokenParams.userBalance = 0;
//         debtTokenParams.totalSupply = 0;

//         assetParams.allowance     = 0;
//         assetParams.userBalance   = 0;
//         assetParams.aTokenBalance = 500 ether;

//         _assertPoolReserveState(poolParams);
//         _assertDebtTokenState(debtTokenParams);
//         _assertAssetState(assetParams);
//     }

//     function _repayLessThanDebtNoTimePassedTest() internal {
//         AssertPoolReserveStateParams memory poolParams = AssertPoolReserveStateParams({
//             asset:                     address(borrowAsset),
//             liquidityIndex:            1e27,
//             currentLiquidityRate:      0.37e27,  // Fully utilized
//             variableBorrowIndex:       1e27,
//             currentVariableBorrowRate: 0.37e27,  // Fully utilized: 5% + 2% + 30%
//             currentStableBorrowRate:   0,
//             lastUpdateTimestamp:       1,
//             accruedToTreasury:         0,
//             unbacked:                  0
//         });

//         AssertDebtTokenStateParams memory debtTokenParams = AssertDebtTokenStateParams({
//             user:        borrower,
//             debtToken:   debtToken,
//             userBalance: 500 ether,
//             totalSupply: 500 ether
//         });

//         AssertAssetStateParams memory assetParams = AssertAssetStateParams({
//             user:          borrower,
//             asset:         address(borrowAsset),
//             allowance:     500 ether - 1,
//             userBalance:   500 ether,
//             aTokenBalance: 0
//         });

//         _assertPoolReserveState(poolParams);
//         _assertDebtTokenState(debtTokenParams);
//         _assertAssetState(assetParams);

//         pool.repayWithATokens(address(borrowAsset), 500 ether - 1, 2);

//         poolParams.currentLiquidityRate      = 1e5;            // 1/500e18 = 2e-21 => 2e-21 * (0.05e27 + 5e4) = 1e5 in ray
//         poolParams.currentVariableBorrowRate = 0.05e27 + 5e4;  // 1/500e18 = 2e-21 => 2e-21/0.8 * 0.02 = 5e-23 = 5e4 in ray

//         debtTokenParams.userBalance = 1;
//         debtTokenParams.totalSupply = 1;

//         assetParams.allowance     = 0;
//         assetParams.userBalance   = 1;
//         assetParams.aTokenBalance = 500 ether - 1;

//         _assertPoolReserveState(poolParams);
//         _assertDebtTokenState(debtTokenParams);
//         _assertAssetState(assetParams);
//     }

//     function _repayMoreThanDebtSomeTimePassedTest() internal {
//         ( uint256 borrowRate, uint256 liquidityRate ) = _getUpdatedRates(500 ether, 500 ether);

//         assertEq(borrowRate,    0.37e27);
//         assertEq(liquidityRate, 0.37e27);

//         uint256 supplierYield = 0.37e27 * 500 ether / 100 / 1e27;  // 1% of APR

//         uint256 compoundedNormalizedInterest = _getCompoundedNormalizedInterest(borrowRate, WARP_TIME);

//         uint256 borrowerDebt = (compoundedNormalizedInterest - 1e27) * 500 ether / 1e27 + 1;  // Rounding

//         borrowAsset.mint(borrower, borrowerDebt + 1);

//         // Borrower owes slightly more than lender has earned because of compounded interest
//         assertEq(supplierYield,                1.85 ether);  // 500 * 0.37 * 1%
//         assertEq(compoundedNormalizedInterest, 1.003706853420131674241446640e27);
//         assertEq(borrowerDebt,                 1.853426710065837121 ether);

//         AssertPoolReserveStateParams memory poolParams = AssertPoolReserveStateParams({
//             asset:                     address(borrowAsset),
//             liquidityIndex:            1e27,
//             currentLiquidityRate:      liquidityRate,  // Fully utilized
//             variableBorrowIndex:       1e27,
//             currentVariableBorrowRate: borrowRate,  // Fully utilized: 5% + 2% + 30%
//             currentStableBorrowRate:   0,
//             lastUpdateTimestamp:       1,
//             accruedToTreasury:         0,
//             unbacked:                  0
//         });

//         AssertDebtTokenStateParams memory debtTokenParams = AssertDebtTokenStateParams({
//             user:        borrower,
//             debtToken:   debtToken,
//             userBalance: 500 ether + borrowerDebt,
//             totalSupply: 500 ether + borrowerDebt
//         });

//         AssertAssetStateParams memory assetParams = AssertAssetStateParams({
//             user:          borrower,
//             asset:         address(borrowAsset),
//             allowance:     500 ether + borrowerDebt + 1,
//             userBalance:   500 ether + borrowerDebt + 1,
//             aTokenBalance: 0
//         });

//         _assertPoolReserveState(poolParams);
//         _assertDebtTokenState(debtTokenParams);
//         _assertAssetState(assetParams);

//         pool.repayWithATokens(address(borrowAsset), 500 ether + borrowerDebt + 1, 2);

//         uint256 expectedLiquidityIndex      = 1e27 + (1e27 * liquidityRate / 100 / 1e27);  // Normalized yield accrues 1% of APR
//         uint256 expectedVariableBorrowIndex = 1e27 * compoundedNormalizedInterest / 1e27;  // Accrues slightly more than 1% of APR because of compounded interest

//         assertEq(expectedLiquidityIndex,      1.0037e27);
//         assertEq(expectedVariableBorrowIndex, 1.003706853420131674241446640e27);

//         poolParams.liquidityIndex            = expectedLiquidityIndex;
//         poolParams.variableBorrowIndex       = expectedVariableBorrowIndex;
//         poolParams.currentLiquidityRate      = 0;
//         poolParams.currentVariableBorrowRate = 0.05e27;
//         poolParams.lastUpdateTimestamp       = WARP_TIME + 1;

//         debtTokenParams.userBalance = 0;
//         debtTokenParams.totalSupply = 0;

//         assetParams.allowance     = 1;  // Didn't use whole allowance
//         assetParams.userBalance   = 1;  // Paid back full balance
//         assetParams.aTokenBalance = 500 ether + borrowerDebt;

//         _assertPoolReserveState(poolParams);
//         _assertDebtTokenState(debtTokenParams);
//         _assertAssetState(assetParams);
//     }

//     function _repayEqualToDebtSomeTimePassedTest() internal {
//         ( uint256 borrowRate, uint256 liquidityRate ) = _getUpdatedRates(500 ether, 500 ether);

//         assertEq(borrowRate,    0.37e27);
//         assertEq(liquidityRate, 0.37e27);

//         uint256 supplierYield = 0.37e27 * 500 ether / 100 / 1e27;  // 1% of APR

//         uint256 compoundedNormalizedInterest = _getCompoundedNormalizedInterest(borrowRate, WARP_TIME);

//         uint256 borrowerDebt = (compoundedNormalizedInterest - 1e27) * 500 ether / 1e27 + 1;  // Rounding

//         borrowAsset.mint(borrower, borrowerDebt);

//         // Borrower owes slightly more than lender has earned because of compounded interest
//         assertEq(supplierYield,                1.85 ether);  // 500 * 0.37 * 1%
//         assertEq(compoundedNormalizedInterest, 1.003706853420131674241446640e27);
//         assertEq(borrowerDebt,                 1.853426710065837121 ether);

//         AssertPoolReserveStateParams memory poolParams = AssertPoolReserveStateParams({
//             asset:                     address(borrowAsset),
//             liquidityIndex:            1e27,
//             currentLiquidityRate:      liquidityRate,  // Fully utilized
//             variableBorrowIndex:       1e27,
//             currentVariableBorrowRate: borrowRate,  // Fully utilized: 5% + 2% + 30%
//             currentStableBorrowRate:   0,
//             lastUpdateTimestamp:       1,
//             accruedToTreasury:         0,
//             unbacked:                  0
//         });

//         AssertDebtTokenStateParams memory debtTokenParams = AssertDebtTokenStateParams({
//             user:        borrower,
//             debtToken:   debtToken,
//             userBalance: 500 ether + borrowerDebt,
//             totalSupply: 500 ether + borrowerDebt
//         });

//         AssertAssetStateParams memory assetParams = AssertAssetStateParams({
//             user:          borrower,
//             asset:         address(borrowAsset),
//             allowance:     500 ether + borrowerDebt,
//             userBalance:   500 ether + borrowerDebt,
//             aTokenBalance: 0
//         });

//         _assertPoolReserveState(poolParams);
//         _assertDebtTokenState(debtTokenParams);
//         _assertAssetState(assetParams);

//         pool.repayWithATokens(address(borrowAsset), 500 ether + borrowerDebt, 2);

//         uint256 expectedLiquidityIndex      = 1e27 + (1e27 * liquidityRate / 100 / 1e27);  // Normalized yield accrues 1% of APR
//         uint256 expectedVariableBorrowIndex = 1e27 * compoundedNormalizedInterest / 1e27;  // Accrues slightly more than 1% of APR because of compounded interest

//         assertEq(expectedLiquidityIndex,      1.0037e27);
//         assertEq(expectedVariableBorrowIndex, 1.003706853420131674241446640e27);

//         poolParams.liquidityIndex            = expectedLiquidityIndex;
//         poolParams.variableBorrowIndex       = expectedVariableBorrowIndex;
//         poolParams.currentLiquidityRate      = 0;
//         poolParams.currentVariableBorrowRate = 0.05e27;
//         poolParams.lastUpdateTimestamp       = WARP_TIME + 1;

//         debtTokenParams.userBalance = 0;
//         debtTokenParams.totalSupply = 0;

//         assetParams.allowance     = 0;
//         assetParams.userBalance   = 0;
//         assetParams.aTokenBalance = 500 ether + borrowerDebt;

//         _assertPoolReserveState(poolParams);
//         _assertDebtTokenState(debtTokenParams);
//         _assertAssetState(assetParams);
//     }

//     function _repayLessThanDebtSomeTimePassedTest() internal {
//         ( uint256 borrowRate, uint256 liquidityRate ) = _getUpdatedRates(500 ether, 500 ether);

//         assertEq(borrowRate,    0.37e27);
//         assertEq(liquidityRate, 0.37e27);

//         uint256 supplierYield = 0.37e27 * 500 ether / 100 / 1e27;  // 1% of APR

//         uint256 compoundedNormalizedInterest = _getCompoundedNormalizedInterest(borrowRate, WARP_TIME);

//         uint256 borrowerDebt = (compoundedNormalizedInterest - 1e27) * 500 ether / 1e27 + 1;  // Rounding

//         borrowAsset.mint(borrower, borrowerDebt - 1);

//         // Borrower owes slightly more than lender has earned because of compounded interest
//         assertEq(supplierYield,                1.85 ether);  // 500 * 0.37 * 1%
//         assertEq(compoundedNormalizedInterest, 1.003706853420131674241446640e27);
//         assertEq(borrowerDebt,                 1.853426710065837121 ether);

//         AssertPoolReserveStateParams memory poolParams = AssertPoolReserveStateParams({
//             asset:                     address(borrowAsset),
//             liquidityIndex:            1e27,
//             currentLiquidityRate:      liquidityRate,  // Fully utilized
//             variableBorrowIndex:       1e27,
//             currentVariableBorrowRate: borrowRate,  // Fully utilized: 5% + 2% + 30%
//             currentStableBorrowRate:   0,
//             lastUpdateTimestamp:       1,
//             accruedToTreasury:         0,
//             unbacked:                  0
//         });

//         AssertDebtTokenStateParams memory debtTokenParams = AssertDebtTokenStateParams({
//             user:        borrower,
//             debtToken:   debtToken,
//             userBalance: 500 ether + borrowerDebt,
//             totalSupply: 500 ether + borrowerDebt
//         });

//         AssertAssetStateParams memory assetParams = AssertAssetStateParams({
//             user:          borrower,
//             asset:         address(borrowAsset),
//             allowance:     500 ether + borrowerDebt - 1,
//             userBalance:   500 ether + borrowerDebt - 1,
//             aTokenBalance: 0
//         });

//         _assertPoolReserveState(poolParams);
//         _assertDebtTokenState(debtTokenParams);
//         _assertAssetState(assetParams);

//         pool.repayWithATokens(address(borrowAsset), 500 ether + borrowerDebt - 1, 2);

//         uint256 expectedLiquidityIndex      = 1e27 + (1e27 * liquidityRate / 100 / 1e27);  // Normalized yield accrues 1% of APR
//         uint256 expectedVariableBorrowIndex = 1e27 * compoundedNormalizedInterest / 1e27;  // Accrues slightly more than 1% of APR because of compounded interest

//         assertEq(expectedLiquidityIndex,      1.0037e27);
//         assertEq(expectedVariableBorrowIndex, 1.003706853420131674241446640e27);

//         poolParams.liquidityIndex            = expectedLiquidityIndex;
//         poolParams.variableBorrowIndex       = expectedVariableBorrowIndex;
//         poolParams.currentLiquidityRate      = 0.99631e5;           // 1/501.853426710065837121e18 = 1.992613e-21 => 1.992613e-21 * (0.05e27 + 4.9815e4) = 0.99631e5 in ray
//         poolParams.currentVariableBorrowRate = 0.05e27 + 4.9815e4;  // 1/501.853426710065837121e18 = 1.992613e-21 => 1.992613e-21/0.8 * 0.02 = 4.9815e4 = 5e4 in ray
//         poolParams.lastUpdateTimestamp       = WARP_TIME + 1;

//         debtTokenParams.userBalance = 1;
//         debtTokenParams.totalSupply = 1;

//         assetParams.allowance     = 0;
//         assetParams.userBalance   = 0;
//         assetParams.aTokenBalance = 500 ether + borrowerDebt - 1;

//         _assertPoolReserveState(poolParams);
//         _assertDebtTokenState(debtTokenParams);
//         _assertAssetState(assetParams);
//     }

// }
