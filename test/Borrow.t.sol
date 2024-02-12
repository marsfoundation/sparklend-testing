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

contract BorrowTestBase is SparkLendTestBase {

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
        _supply(lender, address(borrowAsset), 500 ether);
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

}
