// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { DataTypes } from "aave-v3-core/contracts/protocol/libraries/types/DataTypes.sol";
import { Errors }    from "aave-v3-core/contracts/protocol/libraries/helpers/Errors.sol";


import {
    IERC20,
    IReserveInterestRateStrategy,
    MockERC20,
    SparkLendTestBase
} from "./SparkLendTestBase.sol";

contract RepayTestBase is SparkLendTestBase {

    address borrower = makeAddr("borrower");
    address lender   = makeAddr("lender");

    function setUp() public virtual override {
        super.setUp();

        vm.label(borrower, "borrower");

        // Allow borrowAsset to be collateral to demo collateralAsset accruing interest
        _initCollateral({
            asset:                address(collateralAsset),
            ltv:                  5000,
            liquidationThreshold: 5000,
            liquidationBonus:     100_01
        });

        vm.prank(admin);
        poolConfigurator.setReserveBorrowing(address(borrowAsset), true);

        _supplyAndUseAsCollateral(borrower, address(collateralAsset), 1000 ether);
        _supply(lender, address(borrowAsset), 500 ether);
        _borrow(borrower, address(borrowAsset), 500 ether);
    }

}

contract RepayFailureTests is RepayTestBase {

    function test_repay_whenAmountZero() public {
        vm.expectRevert(bytes(Errors.INVALID_AMOUNT));
        pool.repay(address(borrowAsset), 0, 2, borrower);
    }

    function test_repay_whenAmountIsUint256MaxAndUserNotOwner() public {
        vm.expectRevert(bytes(Errors.NO_EXPLICIT_AMOUNT_TO_REPAY_ON_BEHALF));
        pool.repay(address(borrowAsset), type(uint256).max, 2, borrower);
    }

    // TODO: Believe this code is unreachable because can't be set to inactive when there is active
    //       borrows.
    // function test_repay_whenNotActive() public {
    //     vm.prank(admin);
    //     poolConfigurator.setReserveActive(address(borrowAsset), false);

    //     vm.expectRevert(bytes(Errors.RESERVE_INACTIVE));
    //     pool.repay(address(borrowAsset), 500 ether, 2, borrower);
    // }

    function test_repay_whenPaused() public {
        vm.prank(admin);
        poolConfigurator.setReservePause(address(borrowAsset), true);

        vm.startPrank(borrower);
        borrowAsset.approve(address(pool), 500 ether);

        vm.expectRevert(bytes(Errors.RESERVE_PAUSED));
        pool.repay(address(borrowAsset), 500 ether, 2, borrower);
    }

    // TODO: Determine convention for this
    function test_repay_success_whenFrozen() public {
        vm.prank(admin);
        poolConfigurator.setReserveFreeze(address(borrowAsset), true);

        vm.startPrank(borrower);
        borrowAsset.approve(address(pool), 500 ether);
        pool.repay(address(borrowAsset), 500 ether, 2, borrower);
    }

    function test_repay_noDebt() public {
        vm.expectRevert(bytes(Errors.NO_DEBT_OF_SELECTED_TYPE));
        pool.repay(address(borrowAsset), 500 ether, 2, lender);
    }

    function test_repay_notEnoughApprovalOfUnderlyingBoundary() public {
        vm.startPrank(borrower);
        borrowAsset.approve(address(pool), 500 ether - 1);
        vm.expectRevert(stdError.arithmeticError);
        pool.repay(address(borrowAsset), 500 ether, 2, borrower);

        borrowAsset.approve(address(pool), 500 ether);
        pool.repay(address(borrowAsset), 500 ether, 2, borrower);
    }

    // TODO: Figure out failure from lack of balance
    //       This can be done by specifying an amount that is less than or equal to the current debt but is greater than the user balance.

}

contract RepaySuccessTests is RepayTestBase {

    address debtToken;

    function setUp() public virtual override {
        super.setUp();
        debtToken = pool.getReserveData(address(borrowAsset)).variableDebtTokenAddress;
    }

    modifier givenNoTimeHasPassedSinceBorrow { _; }

    modifier givenSomeTimeHasPassedSinceBorrow() {
        skip(WARP_TIME);
        _;
    }

    modifier givenNotInIsolationMode { _; }

    modifier givenInIsolationMode {
        // Remove liquidity so initial DC can be set
        _repay(borrower, address(borrowAsset), 500 ether);
        _withdraw(borrower, address(collateralAsset), 1000 ether);

        vm.startPrank(admin);
        poolConfigurator.setBorrowableInIsolation(address(borrowAsset), true);
        poolConfigurator.setDebtCeiling(address(collateralAsset), 1000_00);
        vm.stopPrank();

        _supplyAndUseAsCollateral(borrower, address(collateralAsset), 1000 ether);  // Don't have to useAsCollateral again
        _borrow(borrower, address(borrowAsset), 500 ether);
        _;
    }

    modifier whenUserIsPayingGreaterThanDebt {
        // Code to set up the scenario where the user pays more than the debt
        _;
    }

    modifier whenUserIsPayingEqualToDebt {
        // Code to set up the scenario where the user pays exactly the debt amount
        _;
    }

    modifier whenUserIsPayingWithUint256Max {
        // Code to set up the scenario where the user pays with uint256 max value
        _;
    }

    function test_repay_01()
        givenNoTimeHasPassedSinceBorrow
        givenNotInIsolationMode
        public
    {
        assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);

        _repayMoreThanDebtNoTimePassedTest();

        assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);
    }

    function test_repay_02()
        givenNoTimeHasPassedSinceBorrow
        givenNotInIsolationMode
        public
    {
        assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);

        _repayEqualToDebtNoTimePassedTest();

        assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);
    }

    function test_repay_03()
        givenNoTimeHasPassedSinceBorrow
        givenNotInIsolationMode
        public
    {
        assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);

        _repayLessThanDebtNoTimePassedTest();

        assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);
    }

    function test_repay_04()
        givenNoTimeHasPassedSinceBorrow
        givenInIsolationMode
        public
    {
        assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 500_00);

        _repayMoreThanDebtNoTimePassedTest();

        assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);
    }

    function test_repay_05()
        givenNoTimeHasPassedSinceBorrow
        givenInIsolationMode
        public
    {
        assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 500_00);

        _repayEqualToDebtNoTimePassedTest();

        assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);
    }

    function test_repay_06()
        givenNoTimeHasPassedSinceBorrow
        givenInIsolationMode
        public
    {
        assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 500_00);

        _repayLessThanDebtNoTimePassedTest();

        // NOTE: Repaid 500 ether - 1, but since repaid debt is rounded down, the
        //       isolationModeTotalDebt is 0.01 ether.
        assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 1);
    }

    function test_repay_07()
        givenSomeTimeHasPassedSinceBorrow
        givenNotInIsolationMode
        public
    {
        assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);

        _repayMoreThanDebtSomeTimePassedTest();

        assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);
    }

    // function test_repay_08()
    //     givenSomeTimeHasPassedSinceBorrow
    //     givenNotInIsolationMode
    //     public
    // {
    //     assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);

    //     _repayEqualToDebtNoTimePassedTest();

    //     assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);
    // }

    // function test_repay_09()
    //     givenSomeTimeHasPassedSinceBorrow
    //     givenNotInIsolationMode
    //     public
    // {
    //     assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);

    //     _repayLessThanDebtNoTimePassedTest();

    //     assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);
    // }

    // function test_repay_10()
    //     givenSomeTimeHasPassedSinceBorrow
    //     givenInIsolationMode
    //     public
    // {
    //     assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 500_00);

    //     _repayMoreThanDebtSomeTimePassedTest();

    //     assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);
    // }

    // function test_repay_11()
    //     givenSomeTimeHasPassedSinceBorrow
    //     givenInIsolationMode
    //     public
    // {
    //     assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 500_00);

    //     _repayEqualToDebtNoTimePassedTest();

    //     assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);
    // }

    // function test_repay_12()
    //     givenSomeTimeHasPassedSinceBorrow
    //     givenInIsolationMode
    //     public
    // {
    //     assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 500_00);

    //     _repayLessThanDebtNoTimePassedTest();

    //     // NOTE: Repaid 500 ether - 1, but since repaid debt is rounded down, the
    //     //       isolationModeTotalDebt is 0.01 ether.
    //     assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 1);
    // }

    /**********************************************************************************************/
    /*** Test running functions                                                                 ***/
    /**********************************************************************************************/

    function _repayMoreThanDebtNoTimePassedTest() internal {
        vm.startPrank(borrower);
        borrowAsset.approve(address(pool), 500 ether + 1);

        AssertPoolReserveStateParams memory poolParams = AssertPoolReserveStateParams({
            asset:                     address(borrowAsset),
            liquidityIndex:            1e27,
            currentLiquidityRate:      0.37e27,  // Fully utilized
            variableBorrowIndex:       1e27,
            currentVariableBorrowRate: 0.37e27,  // Fully utilized: 5% + 2% + 30%
            currentStableBorrowRate:   0,
            lastUpdateTimestamp:       1,
            accruedToTreasury:         0,
            unbacked:                  0
        });

        AssertDebtTokenStateParams memory debtTokenParams = AssertDebtTokenStateParams({
            user:        borrower,
            debtToken:   debtToken,
            userBalance: 500 ether,
            totalSupply: 500 ether
        });

        AssertAssetStateParams memory assetParams = AssertAssetStateParams({
            user:          borrower,
            asset:         address(borrowAsset),
            allowance:     500 ether + 1,
            userBalance:   500 ether,
            aTokenBalance: 0
        });

        _assertPoolReserveState(poolParams);
        _assertDebtTokenState(debtTokenParams);
        _assertAssetState(assetParams);

        pool.repay(address(borrowAsset), 500 ether + 1, 2, borrower);

        poolParams.currentLiquidityRate      = 0;
        poolParams.currentVariableBorrowRate = 0.05e27;

        debtTokenParams.userBalance = 0;
        debtTokenParams.totalSupply = 0;

        assetParams.allowance     = 1;  // Didn't use whole allowance
        assetParams.userBalance   = 0;  // Paid back full balance
        assetParams.aTokenBalance = 500 ether;

        _assertPoolReserveState(poolParams);
        _assertDebtTokenState(debtTokenParams);
        _assertAssetState(assetParams);
    }

    function _repayEqualToDebtNoTimePassedTest() internal {
        vm.startPrank(borrower);
        borrowAsset.approve(address(pool), 500 ether);

        AssertPoolReserveStateParams memory poolParams = AssertPoolReserveStateParams({
            asset:                     address(borrowAsset),
            liquidityIndex:            1e27,
            currentLiquidityRate:      0.37e27,  // Fully utilized
            variableBorrowIndex:       1e27,
            currentVariableBorrowRate: 0.37e27,  // Fully utilized: 5% + 2% + 30%
            currentStableBorrowRate:   0,
            lastUpdateTimestamp:       1,
            accruedToTreasury:         0,
            unbacked:                  0
        });

        AssertDebtTokenStateParams memory debtTokenParams = AssertDebtTokenStateParams({
            user:        borrower,
            debtToken:   debtToken,
            userBalance: 500 ether,
            totalSupply: 500 ether
        });

        AssertAssetStateParams memory assetParams = AssertAssetStateParams({
            user:          borrower,
            asset:         address(borrowAsset),
            allowance:     500 ether,
            userBalance:   500 ether,
            aTokenBalance: 0
        });

        _assertPoolReserveState(poolParams);
        _assertDebtTokenState(debtTokenParams);
        _assertAssetState(assetParams);

        pool.repay(address(borrowAsset), 500 ether, 2, borrower);

        poolParams.currentLiquidityRate      = 0;
        poolParams.currentVariableBorrowRate = 0.05e27;

        debtTokenParams.userBalance = 0;
        debtTokenParams.totalSupply = 0;

        assetParams.allowance     = 0;
        assetParams.userBalance   = 0;
        assetParams.aTokenBalance = 500 ether;

        _assertPoolReserveState(poolParams);
        _assertDebtTokenState(debtTokenParams);
        _assertAssetState(assetParams);
    }

    function _repayLessThanDebtNoTimePassedTest() internal {
        vm.startPrank(borrower);
        borrowAsset.approve(address(pool), 500 ether - 1);

        AssertPoolReserveStateParams memory poolParams = AssertPoolReserveStateParams({
            asset:                     address(borrowAsset),
            liquidityIndex:            1e27,
            currentLiquidityRate:      0.37e27,  // Fully utilized
            variableBorrowIndex:       1e27,
            currentVariableBorrowRate: 0.37e27,  // Fully utilized: 5% + 2% + 30%
            currentStableBorrowRate:   0,
            lastUpdateTimestamp:       1,
            accruedToTreasury:         0,
            unbacked:                  0
        });

        AssertDebtTokenStateParams memory debtTokenParams = AssertDebtTokenStateParams({
            user:        borrower,
            debtToken:   debtToken,
            userBalance: 500 ether,
            totalSupply: 500 ether
        });

        AssertAssetStateParams memory assetParams = AssertAssetStateParams({
            user:          borrower,
            asset:         address(borrowAsset),
            allowance:     500 ether - 1,
            userBalance:   500 ether,
            aTokenBalance: 0
        });

        _assertPoolReserveState(poolParams);
        _assertDebtTokenState(debtTokenParams);
        _assertAssetState(assetParams);

        pool.repay(address(borrowAsset), 500 ether - 1, 2, borrower);

        poolParams.currentLiquidityRate      = 1e5;            // 1/500e18 = 2e-21 => 2e-21 * (0.05e27 + 5e4) = 1e5 in ray
        poolParams.currentVariableBorrowRate = 0.05e27 + 5e4;  // 1/500e18 = 2e-21 => 2e-21/0.8 * 0.02 = 5e-23 = 5e4 in ray

        debtTokenParams.userBalance = 1;
        debtTokenParams.totalSupply = 1;

        assetParams.allowance     = 0;
        assetParams.userBalance   = 1;
        assetParams.aTokenBalance = 500 ether - 1;

        _assertPoolReserveState(poolParams);
        _assertDebtTokenState(debtTokenParams);
        _assertAssetState(assetParams);
    }

    function _repayMoreThanDebtSomeTimePassedTest() internal {
        vm.startPrank(borrower);
        borrowAsset.approve(address(pool), 500 ether + 1);

        ( uint256 borrowRate, uint256 liquidityRate ) = _getUpdatedRates(500 ether, 500 ether);

        assertEq(borrowRate,    0.37e27);
        assertEq(liquidityRate, 0.37e27);

        uint256 supplierYield = 0.37e27 * 500 ether / 100 / 1e27;  // 1% of APR

        uint256 compoundedNormalizedInterest = _getCompoundedNormalizedInterest(borrowRate, WARP_TIME);

        uint256 borrowerDebt = (compoundedNormalizedInterest - 1e27) * 500 ether / 1e27;

        // Borrower owes slightly more than lender has earned because of compounded interest
        assertEq(supplierYield,                185 ether);  // 500 * 0.37
        assertEq(compoundedNormalizedInterest, 1.000550151275656075434506e27);
        assertEq(borrowerDebt,                 0.055015127565607543 ether);

        // AssertPoolReserveStateParams memory poolParams = AssertPoolReserveStateParams({
        //     asset:                     address(borrowAsset),
        //     liquidityIndex:            1e27,
        //     currentLiquidityRate:      0.37e27,  // Fully utilized
        //     variableBorrowIndex:       1e27,
        //     currentVariableBorrowRate: 0.37e27,  // Fully utilized: 5% + 2% + 30%
        //     currentStableBorrowRate:   0,
        //     lastUpdateTimestamp:       1,
        //     accruedToTreasury:         0,
        //     unbacked:                  0
        // });

        // AssertDebtTokenStateParams memory debtTokenParams = AssertDebtTokenStateParams({
        //     user:        borrower,
        //     debtToken:   debtToken,
        //     userBalance: 500 ether,
        //     totalSupply: 500 ether
        // });

        // AssertAssetStateParams memory assetParams = AssertAssetStateParams({
        //     user:          borrower,
        //     asset:         address(borrowAsset),
        //     allowance:     500 ether + 1,
        //     userBalance:   500 ether,
        //     aTokenBalance: 0
        // });

        // _assertPoolReserveState(poolParams);
        // _assertDebtTokenState(debtTokenParams);
        // _assertAssetState(assetParams);

        // console.log("bal      ", borrowAsset.balanceOf(borrower));
        // console.log("allowance", borrowAsset.allowance(borrower, address(pool)));

        // pool.repay(address(borrowAsset), 500 ether + 1, 2, borrower);

        // poolParams.currentLiquidityRate      = 0;
        // poolParams.currentVariableBorrowRate = 0.05e27;

        // debtTokenParams.userBalance = 0;
        // debtTokenParams.totalSupply = 0;

        // assetParams.allowance     = 1;  // Didn't use whole allowance
        // assetParams.userBalance   = 0;  // Paid back full balance
        // assetParams.aTokenBalance = 500 ether;

        // _assertPoolReserveState(poolParams);
        // _assertDebtTokenState(debtTokenParams);
        // _assertAssetState(assetParams);
    }


}
