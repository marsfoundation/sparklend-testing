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

}
