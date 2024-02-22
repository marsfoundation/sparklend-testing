// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { UserConfiguration } from "aave-v3-core/contracts/protocol/libraries/configuration/UserConfiguration.sol";
import { Errors }            from "aave-v3-core/contracts/protocol/libraries/helpers/Errors.sol";
import { DataTypes }         from "aave-v3-core/contracts/protocol/libraries/types/DataTypes.sol";

import {
    IERC20,
    IReserveInterestRateStrategy,
    MockERC20,
    SparkLendTestBase
} from "./SparkLendTestBase.sol";

import { MockOracleSentinel } from "test/mocks/MockOracleSentinel.sol";

contract BorrowTestBase is SparkLendTestBase {

    address borrower = makeAddr("borrower");
    address lender   = makeAddr("lender");

    function setUp() public virtual override {
        super.setUp();

        vm.label(borrower, "borrower");

        _initCollateral({
            asset:                address(collateralAsset),
            ltv:                  50_00,
            liquidationThreshold: 50_00,
            liquidationBonus:     100_01
        });

        vm.prank(admin);
        poolConfigurator.setReserveBorrowing(address(borrowAsset), true);

        _supplyAndUseAsCollateral(borrower, address(collateralAsset), 1000 ether);
        _supply(lender, address(borrowAsset), 1000 ether);
    }

}

contract BorrowFailureTests is BorrowTestBase {

    function test_borrow_whenAmountZero() public {
        vm.expectRevert(bytes(Errors.INVALID_AMOUNT));
        pool.borrow(address(borrowAsset), 0, 2, 0, borrower);
    }

    // TODO: Believe this code is unreachable because can't be set to inactive when there is active
    //       supplies.
    // function test_borrow_whenNotActive() public {
    //     vm.prank(admin);
    //     poolConfigurator.setReserveActive(address(borrowAsset), false);

    //     vm.expectRevert(bytes(Errors.RESERVE_INACTIVE));
    //     pool.borrow(address(borrowAsset), 500 ether, 2, 0, borrower);
    // }

    function test_borrow_whenPaused() public {
        vm.prank(admin);
        poolConfigurator.setReservePause(address(borrowAsset), true);

        vm.expectRevert(bytes(Errors.RESERVE_PAUSED));
        pool.borrow(address(borrowAsset), 500 ether, 2, 0, borrower);
    }

    function test_borrow_whenFrozen() public {
        vm.prank(admin);
        poolConfigurator.setReserveFreeze(address(borrowAsset), true);

        vm.expectRevert(bytes(Errors.RESERVE_FROZEN));
        pool.borrow(address(borrowAsset), 500 ether, 2, 0, borrower);
    }

    function test_borrow_whenBorrowNotEnabled() public {
        vm.prank(admin);
        poolConfigurator.setReserveBorrowing(address(borrowAsset), false);

        vm.expectRevert(bytes(Errors.BORROWING_NOT_ENABLED));
        pool.borrow(address(borrowAsset), 500 ether, 2, 0, borrower);
    }

    function test_borrow_whenOracleSentinelNotBorrowAllowed() public {
        vm.startPrank(admin);
        poolAddressesProvider.setPriceOracleSentinel(address(new MockOracleSentinel()));
        vm.stopPrank();

        vm.expectRevert(bytes(Errors.PRICE_ORACLE_SENTINEL_CHECK_FAILED));
        pool.borrow(address(borrowAsset), 500 ether, 2, 0, borrower);
    }

    function test_borrow_invalidBorrowType() public {
        vm.expectRevert(bytes(Errors.INVALID_INTEREST_RATE_MODE_SELECTED));
        pool.borrow(address(borrowAsset), 500 ether, 0, 0, borrower);
    }

    function test_borrow_borrowCapExceededBoundary() public {
        vm.prank(admin);
        poolConfigurator.setBorrowCap(address(borrowAsset), 500);

        vm.startPrank(borrower);

        vm.expectRevert(bytes(Errors.BORROW_CAP_EXCEEDED));
        pool.borrow(address(borrowAsset), 500 ether + 1, 2, 0, borrower);

        pool.borrow(address(borrowAsset), 500 ether, 2, 0, borrower);
    }

    function test_borrow_userInIsolationModeAssetIsNot() external {
        // Remove liquidity so initial DC can be set
        _withdraw(borrower, address(collateralAsset), 1000 ether);

        vm.prank(admin);
        poolConfigurator.setDebtCeiling(address(collateralAsset), 500);  // Activate isolation mode

        _supplyAndUseAsCollateral(borrower, address(collateralAsset), 1000 ether);

        vm.expectRevert(bytes(Errors.ASSET_NOT_BORROWABLE_IN_ISOLATION));
        pool.borrow(address(borrowAsset), 500 ether, 2, 0, borrower);
    }

    function test_borrow_isolationModeDebtCeilingSurpassedBoundary() external {
        // Remove liquidity so initial DC can be set
        _withdraw(borrower, address(collateralAsset), 1000 ether);

        vm.startPrank(admin);
        poolConfigurator.setDebtCeiling(address(collateralAsset), 400_00);  // Activate isolation mode
        poolConfigurator.setBorrowableInIsolation(address(borrowAsset), true);
        vm.stopPrank();

        _supplyAndUseAsCollateral(borrower, address(collateralAsset), 1000 ether);

        vm.startPrank(borrower);

        // NOTE: Setting DC to 400 so LTV isn't exceeded on boundary
        vm.expectRevert(bytes(Errors.DEBT_CEILING_EXCEEDED));
        pool.borrow(address(borrowAsset), 400.01 ether, 2, 0, borrower);

        // Rounds down to 400.00 here so boundary is 400.01 ether - 1
        pool.borrow(address(borrowAsset), 400.01 ether - 1, 2, 0, borrower);
    }

    function test_borrow_emodeCategoryMismatch() external {
        vm.startPrank(admin);
        poolConfigurator.setEModeCategory({
            categoryId:           1,
            ltv:                  50_00,
            liquidationThreshold: 60_00,
            liquidationBonus:     101_00,
            oracle:               address(0),
            label:                "emode1"
        });

        poolConfigurator.setAssetEModeCategory(address(collateralAsset), 1);

        vm.stopPrank();
        vm.startPrank(borrower);

        pool.setUserEMode(1);

        vm.expectRevert(bytes(Errors.INCONSISTENT_EMODE_CATEGORY));
        pool.borrow(address(borrowAsset), 500 ether, 2, 0, borrower);
    }

    function test_borrow_userHasZeroCollateral() public {
        _withdraw(borrower, address(collateralAsset), 1000 ether);

        vm.prank(borrower);
        vm.expectRevert(bytes(Errors.COLLATERAL_BALANCE_IS_ZERO));
        pool.borrow(address(borrowAsset), 500 ether, 2, 0, borrower);
    }

    function test_borrow_userHasZeroLtv() public {
        vm.prank(admin);
        poolConfigurator.configureReserveAsCollateral(address(collateralAsset), 0, 50_00, 101_00);

        vm.prank(borrower);
        vm.expectRevert(bytes(Errors.LTV_VALIDATION_FAILED));
        pool.borrow(address(borrowAsset), 500 ether, 2, 0, borrower);
    }

    function test_borrow_userHasHealthFactorBelowZero() public {
        vm.startPrank(borrower);
        pool.borrow(address(borrowAsset), 500 ether, 2, 0, borrower);

        vm.warp(365 days);

        vm.expectRevert(bytes(Errors.HEALTH_FACTOR_LOWER_THAN_LIQUIDATION_THRESHOLD));
        pool.borrow(address(borrowAsset), 1, 2, 0, borrower);
    }

    function test_borrow_userPutsPositionBelowLtvBoundary() public {
        vm.startPrank(borrower);
        vm.expectRevert(bytes(Errors.COLLATERAL_CANNOT_COVER_NEW_BORROW));
        pool.borrow(address(borrowAsset), 500 ether + 1e10, 2, 0, borrower);

        // Rounds down to 500e8 here so boundary is 500 ether - 1e10
        pool.borrow(address(borrowAsset), 500 ether + 1e10 - 1, 2, 0, borrower);
    }

    function test_borrow_userChoosesStableBorrow() public {
        vm.startPrank(borrower);
        vm.expectRevert(bytes(Errors.STABLE_BORROWING_NOT_ENABLED));
        pool.borrow(address(borrowAsset), 500 ether, 1, 0, borrower);
    }

    function test_borrow_assetNotUserSiloedAssetAddress() public {
        _initCollateral({
            asset:                address(borrowAsset),
            ltv:                  50_00,
            liquidationThreshold: 50_00,
            liquidationBonus:     100_01
        });

        vm.startPrank(admin);
        poolConfigurator.setReserveBorrowing(address(collateralAsset), true);
        poolConfigurator.setSiloedBorrowing(address(collateralAsset), true);
        vm.stopPrank();

        // Supply and borrow with the opposite assets so user is siloed borrowing
        // with collateralAsset
        _supplyAndUseAsCollateral(borrower, address(borrowAsset), 1000 ether);
        _borrow(borrower, address(collateralAsset), 500 ether);

        vm.expectRevert(bytes(Errors.SILOED_BORROWING_VIOLATION));
        pool.borrow(address(borrowAsset), 500 ether, 2, 0, borrower);
    }

    // TODO: Revisit - Don't think this code is reachable because the user getSiloedBorrowingState
    //       function calls reserveConfig.getSiloedBorrowing()
    // function test_borrow_userNotSiloedButAssetIs() public {}

}

contract BorrowConcreteTests is BorrowTestBase {

    using UserConfiguration for DataTypes.UserConfigurationMap;

    address debtToken;

    function setUp() public virtual override {
        super.setUp();
        debtToken = pool.getReserveData(address(borrowAsset)).variableDebtTokenAddress;
    }

    modifier whenItIsUsersFirstBorrow { _; }

    modifier whenThereIsAnExistingBorrow {
        address borrower2 = makeAddr("borrower2");

        _supplyAndUseAsCollateral(borrower2, address(collateralAsset), 1000 ether);
        _borrow(borrower2, address(borrowAsset), 100 ether);
        _;
    }

    modifier whenNoTimeHasPassedSinceLastBorrow { _; }

    modifier whenSomeTimeHasPassedSinceLastBorrow {
        skip(WARP_TIME);
        _;
    }

    modifier whenUserIsDoingRegularBorrow { _; }

    modifier whenUserIsDoingSiloedBorrow {
        address borrower2 = makeAddr("borrower2");

        bool secondBorrower = aCollateralAsset.balanceOf(borrower2) != 0;

        uint256 existingBorrower2Balance;

        if (secondBorrower) {
            existingBorrower2Balance = IERC20(debtToken).balanceOf(address(borrower2));
            _repay(borrower2, address(borrowAsset), existingBorrower2Balance);
            _withdraw(borrower2, address(collateralAsset), 1000 ether);
        }

        vm.prank(admin);
        poolConfigurator.setSiloedBorrowing(address(borrowAsset), true);

        if (secondBorrower) {
            _supplyAndUseAsCollateral(borrower2, address(collateralAsset), 1000 ether);
            _borrow(borrower2, address(borrowAsset), existingBorrower2Balance);
        }

        _;
    }

    modifier whenUserIsDoingEModeBorrow {
        vm.startPrank(admin);
        poolConfigurator.setEModeCategory({
            categoryId:           1,
            ltv:                  50_00,
            liquidationThreshold: 60_00,
            liquidationBonus:     101_00,
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

    modifier whenUserIsDoingIsolationModeBorrow {
        // Remove liquidity so initial DC can be set
        _withdraw(borrower, address(collateralAsset), 1000 ether);

        address borrower2 = makeAddr("borrower2");

        bool secondBorrower = aCollateralAsset.balanceOf(borrower2) != 0;

        if (secondBorrower) {
            _repay(borrower2, address(borrowAsset), 500 ether);
            _withdraw(borrower2, address(collateralAsset), 1000 ether);
        }

        vm.startPrank(admin);
        poolConfigurator.setDebtCeiling(address(collateralAsset), 1000_00);  // Activate isolation mode
        poolConfigurator.setBorrowableInIsolation(address(borrowAsset), true);
        vm.stopPrank();

        _supplyAndUseAsCollateral(borrower, address(collateralAsset), 1000 ether);

        if (secondBorrower) {
            _supplyAndUseAsCollateral(borrower2, address(collateralAsset), 1000 ether);
            _borrow(borrower2, address(borrowAsset), 500 ether);
        }
        _;
    }

    function test_borrow_01()
        public
        whenItIsUsersFirstBorrow
        whenUserIsDoingRegularBorrow
    {
        assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);

        _usersFirstBorrowTest();

        assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);
    }

    function test_borrow_02()
        public
        whenItIsUsersFirstBorrow
        whenUserIsDoingSiloedBorrow
    {
        assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);

        _usersFirstBorrowTest();

        assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);
    }

    function test_borrow_03()
        public
        whenItIsUsersFirstBorrow
        whenUserIsDoingEModeBorrow
    {
        assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);

        _usersFirstBorrowTest();

        assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);
    }

    function test_borrow_04()
        public
        whenItIsUsersFirstBorrow
        whenUserIsDoingIsolationModeBorrow
    {
        assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);

        _usersFirstBorrowTest();

        assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 500_00);
    }

    function test_borrow_05()
        public
        whenThereIsAnExistingBorrow
        whenNoTimeHasPassedSinceLastBorrow
        whenUserIsDoingRegularBorrow
    {
        assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);

        _existingBorrowNoTimePassedTest();

        assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);
    }

    function test_borrow_06()
        public
        whenThereIsAnExistingBorrow
        whenNoTimeHasPassedSinceLastBorrow
        whenUserIsDoingSiloedBorrow
    {
        assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);

        _existingBorrowNoTimePassedTest();

        assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);
    }

    function test_borrow_07()
        public
        whenThereIsAnExistingBorrow
        whenNoTimeHasPassedSinceLastBorrow
        whenUserIsDoingEModeBorrow
    {
        assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);

        _existingBorrowNoTimePassedTest();

        assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);
    }

    function test_borrow_08()
        public
        whenThereIsAnExistingBorrow
        whenNoTimeHasPassedSinceLastBorrow
        whenUserIsDoingIsolationModeBorrow
    {
        assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 500_00);

        _existingBorrowNoTimePassedTest();

        assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 1000_00);
    }

    function test_borrow_09()
        public
        whenThereIsAnExistingBorrow
        whenSomeTimeHasPassedSinceLastBorrow
        whenUserIsDoingRegularBorrow
    {
        assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);

        _existingBorrowSomeTimePassedTest();

        assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);
    }

    function test_borrow_10()
        public
        whenThereIsAnExistingBorrow
        whenSomeTimeHasPassedSinceLastBorrow
        whenUserIsDoingSiloedBorrow
    {
        assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);

        _existingBorrowSomeTimePassedTest();

        assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);
    }

    function test_borrow_11()
        public
        whenThereIsAnExistingBorrow
        whenSomeTimeHasPassedSinceLastBorrow
        whenUserIsDoingEModeBorrow
    {
        assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);

        _existingBorrowSomeTimePassedTest();

        assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 0);
    }

    function test_borrow_12()
        public
        whenThereIsAnExistingBorrow
        whenSomeTimeHasPassedSinceLastBorrow
        whenUserIsDoingIsolationModeBorrow
    {
        assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 500_00);

        _existingBorrowSomeTimePassedTest();

        assertEq(pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt, 1000_00);
    }

    /**********************************************************************************************/
    /*** Test running functions                                                                 ***/
    /**********************************************************************************************/

    function _usersFirstBorrowTest() internal {
        AssertPoolReserveStateParams memory poolParams = AssertPoolReserveStateParams({
            asset:                     address(borrowAsset),
            liquidityIndex:            1e27,
            currentLiquidityRate:      0,
            variableBorrowIndex:       1e27,
            currentVariableBorrowRate: 0.05e27,
            currentStableBorrowRate:   0,
            lastUpdateTimestamp:       1,
            accruedToTreasury:         0,
            unbacked:                  0
        });

        AssertDebtTokenStateParams memory debtTokenParams = AssertDebtTokenStateParams({
            user:        borrower,
            debtToken:   debtToken,
            userBalance: 0,
            totalSupply: 0
        });

        AssertAssetStateParams memory assetParams = AssertAssetStateParams({
            user:          borrower,
            asset:         address(borrowAsset),
            allowance:     0,
            userBalance:   0,
            aTokenBalance: 1000 ether
        });

        _assertPoolReserveState(poolParams);
        _assertDebtTokenState(debtTokenParams);
        _assertAssetState(assetParams);

        assertEq(pool.getUserConfiguration(borrower).isBorrowingAny(), false);

        vm.prank(borrower);
        pool.borrow(address(borrowAsset), 500 ether, 2, 0, borrower);

        poolParams.currentLiquidityRate      = 0.03125e27;  // Half utilized: 6.25 * 50% = 3.125%
        poolParams.currentVariableBorrowRate = 0.0625e27;   // Half utilized: 5% + 50%/80% * 2% = 6.25%

        debtTokenParams.userBalance = 500 ether;
        debtTokenParams.totalSupply = 500 ether;

        assetParams.aTokenBalance = 500 ether;
        assetParams.userBalance   = 500 ether;

        _assertPoolReserveState(poolParams);
        _assertDebtTokenState(debtTokenParams);
        _assertAssetState(assetParams);

        assertEq(pool.getUserConfiguration(borrower).isBorrowingAny(), true);
    }

    function _existingBorrowNoTimePassedTest() internal {
        AssertPoolReserveStateParams memory poolParams = AssertPoolReserveStateParams({
            asset:                     address(borrowAsset),
            liquidityIndex:            1e27,
            currentLiquidityRate:      0.00525e27,
            variableBorrowIndex:       1e27,
            currentVariableBorrowRate: 0.0525e27,
            currentStableBorrowRate:   0,
            lastUpdateTimestamp:       1,
            accruedToTreasury:         0,
            unbacked:                  0
        });

        AssertDebtTokenStateParams memory debtTokenParams = AssertDebtTokenStateParams({
            user:        borrower,
            debtToken:   debtToken,
            userBalance: 0,
            totalSupply: 100 ether
        });

        AssertAssetStateParams memory assetParams = AssertAssetStateParams({
            user:          borrower,
            asset:         address(borrowAsset),
            allowance:     0,
            userBalance:   0,
            aTokenBalance: 900 ether
        });

        _assertPoolReserveState(poolParams);
        _assertDebtTokenState(debtTokenParams);
        _assertAssetState(assetParams);

        vm.prank(borrower);
        pool.borrow(address(borrowAsset), 500 ether, 2, 0, borrower);

        poolParams.currentLiquidityRate      = 0.039e27;  // 60% utilized: 60% * 6.5% = 3.9%
        poolParams.currentVariableBorrowRate = 0.065e27;  // 60% utilized: 5% + 60%/80% * 2% = 6.5%

        debtTokenParams.userBalance = 500 ether;
        debtTokenParams.totalSupply = 600 ether;

        assetParams.aTokenBalance = 400 ether;
        assetParams.userBalance   = 500 ether;

        _assertPoolReserveState(poolParams);
        _assertDebtTokenState(debtTokenParams);
        _assertAssetState(assetParams);
    }

    function _existingBorrowSomeTimePassedTest() internal {
        AssertPoolReserveStateParams memory poolParams = AssertPoolReserveStateParams({
            asset:                     address(borrowAsset),
            liquidityIndex:            1e27,
            currentLiquidityRate:      0.00525e27,
            variableBorrowIndex:       1e27,
            currentVariableBorrowRate: 0.0525e27,
            currentStableBorrowRate:   0,
            lastUpdateTimestamp:       1,
            accruedToTreasury:         0,
            unbacked:                  0
        });

        uint256 compoundedNormalizedInterest
            = _getCompoundedNormalizedInterest(0.0525e27, WARP_TIME);

        uint256 borrowerDebt = (compoundedNormalizedInterest - 1e27) * 100 ether / 1e27;

        assertEq(borrowerDebt,                 0.052513783297156325 ether);
        assertEq(compoundedNormalizedInterest, 1.000525137832971563250670960e27);

        AssertDebtTokenStateParams memory debtTokenParams = AssertDebtTokenStateParams({
            user:        borrower,
            debtToken:   debtToken,
            userBalance: 0,
            totalSupply: 100 ether + borrowerDebt
        });

        AssertAssetStateParams memory assetParams = AssertAssetStateParams({
            user:          borrower,
            asset:         address(borrowAsset),
            allowance:     0,
            userBalance:   0,
            aTokenBalance: 900 ether
        });

        _assertPoolReserveState(poolParams);
        _assertDebtTokenState(debtTokenParams);
        _assertAssetState(assetParams);

        vm.prank(borrower);
        pool.borrow(address(borrowAsset), 500 ether, 2, 0, borrower);

        ( uint256 borrowRate, uint256 liquidityRate )
            = _getUpdatedRates(600 ether + borrowerDebt, 1000 ether + borrowerDebt);

        assertEq(borrowRate,    0.065000525110257445296653722e27);  // ~60% utilized: 5% + 60%/80% * 2% = ~6.5%
        assertEq(liquidityRate, 0.039001680363853456248262541e27);  // ~60% utilized: 60% * ~6.5% = ~3.9%

        uint256 expectedLiquidityIndex      = 1e27 + (1e27 * 0.00525e27 / 100 / 1e27);      // Normalized yield accrues 1% of APR
        uint256 expectedVariableBorrowIndex = 1e27 * compoundedNormalizedInterest / 1e27;  // Accrues slightly more than 1% of APR because of compounded interest

        assertEq(expectedLiquidityIndex,      1.0000525e27);
        assertEq(expectedVariableBorrowIndex, compoundedNormalizedInterest);

        poolParams.liquidityIndex            = expectedLiquidityIndex;
        poolParams.currentLiquidityRate      = liquidityRate + 1;  // Rounding
        poolParams.variableBorrowIndex       = expectedVariableBorrowIndex;
        poolParams.currentVariableBorrowRate = borrowRate + 1;  // Rounding
        poolParams.lastUpdateTimestamp       = WARP_TIME + 1;

        // Borrower debt only accrued against existing borrow
        debtTokenParams.userBalance = 500 ether;
        debtTokenParams.totalSupply = 600 ether + borrowerDebt;

        assetParams.aTokenBalance = 400 ether;
        assetParams.userBalance   = 500 ether;

        _assertPoolReserveState(poolParams);
        _assertDebtTokenState(debtTokenParams);
        _assertAssetState(assetParams);
    }

}
