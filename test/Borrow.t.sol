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

    address debtToken;

    function setUp() public virtual override {
        super.setUp();
        debtToken = pool.getReserveData(address(borrowAsset)).variableDebtTokenAddress;
    }

    modifier whenNoTimeHasPassedSinceLastBorrow { _; }

    modifier whenSomeTimeHasPassedSinceLastBorrow {
        skip(WARP_TIME);
        _;
    }

    modifier whenUserFirstBorrow { _; }

    modifier whenUserIsDoingRegularBorrow { _; }

    modifier whenUserIsDoingSiloedBorrow {
        // TODO
        _;
    }

    modifier whenUserIsDoingEModeBorrow{
        // TODO
        _;
    }

    modifier whenUserIsDoingIsolationModeBorrow {
        // TODO
        _;
    }

    function test_borrow_01() public {
        vm.startPrank(borrower);

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
    }

}
