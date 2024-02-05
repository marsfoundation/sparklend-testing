// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { Errors } from "aave-v3-core/contracts/protocol/libraries/helpers/Errors.sol";

import {
    IERC20,
    IReserveInterestRateStrategy,
    MockERC20,
    SparkLendTestBase
} from "./SparkLendTestBase.sol";

contract WithdrawTestBase is SparkLendTestBase {

    address user = makeAddr("user");

    function setUp() public virtual override {
        super.setUp();

        _supply(user, address(collateralAsset), 1000 ether);
    }

}

contract WithdrawFailureTests is WithdrawTestBase {

    function test_withdraw_amountZero() public {
        vm.expectRevert(bytes(Errors.INVALID_AMOUNT));
        pool.withdraw(address(collateralAsset), 0, user);
    }

    function test_withdraw_amountGtBalanceBoundary() public {
        vm.startPrank(user);
        vm.expectRevert(bytes(Errors.NOT_ENOUGH_AVAILABLE_USER_BALANCE));
        pool.withdraw(address(collateralAsset), 1000 ether + 1, user);

        pool.withdraw(address(collateralAsset), 1000 ether, user);
    }

    // TODO: Unreachable code - setReserveActive reverts with RESERVE_LIQUIDITY_NOT_ZERO, can't withdraw without liquidity
    // function test_withdraw_whenNotActive() public {
    //     vm.prank(admin);
    //     poolConfigurator.setReserveActive(address(collateralAsset), false);

    //     vm.expectRevert(bytes(Errors.RESERVE_INACTIVE));
    //     pool.withdraw(address(collateralAsset), 1000 ether, user);
    // }

    function test_withdraw_whenPaused() public {
        vm.prank(admin);
        poolConfigurator.setReservePause(address(collateralAsset), true);

        vm.prank(user);
        vm.expectRevert(bytes(Errors.RESERVE_PAUSED));
        pool.withdraw(address(collateralAsset), 1000 ether, user);
    }

    // TODO: Extra test, determine convention for this
    function test_withdraw_success_whenFrozen() public {
        vm.prank(admin);
        poolConfigurator.setReserveFreeze(address(collateralAsset), true);

        vm.prank(user);
        pool.withdraw(address(collateralAsset), 1000 ether, user);
    }

    function test_withdraw_healthFactorBelowThresholdBoundary() public {
        _initCollateral({
            asset:                address(collateralAsset),
            ltv:                  5000,
            liquidationThreshold: 5000,
            liquidationBonus:     100_01
        });

        vm.prank(user);
        pool.setUserUseReserveAsCollateral(address(collateralAsset), true);

        vm.prank(admin);
        poolConfigurator.setReserveBorrowing(address(borrowAsset), true);

        _supply(makeAddr("supplier"), address(borrowAsset), 250 ether);
        _borrow(user, address(borrowAsset), 250 ether);

        // NOTE: 1e10 used for boundary since HF calculations are done in 1e8 precision
        vm.startPrank(user);

        vm.expectRevert(bytes(Errors.HEALTH_FACTOR_LOWER_THAN_LIQUIDATION_THRESHOLD));
        pool.withdraw(address(collateralAsset), 500 ether + 1e10 + 1, user);

        pool.withdraw(address(collateralAsset), 500 ether + 1e10, user);
    }

    // TODO: Believe that this code is unreachable because the LTV is checked in two places
    //       and this only fails if one is zero and the other is not.
    // function test_withdraw_LtvValidationFailed() {}

}

contract WithdrawConcreteTests is WithdrawTestBase {

    modifier givenNoTimeHasPassedAfterSupply { _; }

    modifier givenSomeTimeHasPassedAfterSupply() {
        skip(WARP_TIME);
        _;
    }

    modifier givenNoActiveBorrow { _; }

    modifier givenActiveBorrow {
        // Allow borrowAsset to be collateral to demo collateralAsset accruing interest
        _initCollateral({
            asset:                address(borrowAsset),
            ltv:                  5000,
            liquidationThreshold: 6000,
            liquidationBonus:     100_01
        });

        vm.prank(admin);
        poolConfigurator.setReserveBorrowing(address(collateralAsset), true);

        address borrower = makeAddr("borrower");
        _supplyAndUseAsCollateral(borrower, address(borrowAsset), 1000 ether);
        _borrow(borrower, address(collateralAsset), 100 ether);
        _;
    }

    modifier givenNoTimeHasPassedAfterBorrow { _; }

    modifier givenSomeTimeHasPassedAfterBorrow() {
        skip(WARP_TIME);
        _;
    }

    function test_withdraw_01()
        givenNoTimeHasPassedAfterSupply
        givenNoActiveBorrow
        logStateDiff
        public
    {
        _assertPoolReserveState({
            liquidityIndex:            1e27,
            currentLiquidityRate:      0,
            variableBorrowIndex:       1e27,
            currentVariableBorrowRate: 0,
            currentStableBorrowRate:   0,
            lastUpdateTimestamp:       0,
            accruedToTreasury:         0,
            unbacked:                  0
        });

        _assertATokenStateWithdraw({
            userBalance: 0,
            totalSupply: 0
        });

        _assertAssetStateWithdraw({
            allowance:     1000 ether,
            userBalance:   1000 ether,
            aTokenBalance: 0
        });

        vm.prank(user);
        pool.withdraw(address(collateralAsset), 500 ether, user);
    }

    /**********************************************************************************************/
    /*** Assertion helper functions                                                             ***/
    /**********************************************************************************************/

    function _assertAssetStateWithdraw(
        uint256 allowance,
        uint256 userBalance,
        uint256 aTokenBalance
    )
        internal
    {
        _assertAssetState({
            user:          user,
            allowance:     allowance,
            userBalance:   userBalance,
            aTokenBalance: aTokenBalance
        });
    }

    function _assertATokenStateWithdraw(uint256 userBalance, uint256 totalSupply) internal {
        _assertATokenState({
            user:        user,
            aToken:      address(aCollateralAsset),
            userBalance: userBalance,
            totalSupply: totalSupply
        });
    }

}
