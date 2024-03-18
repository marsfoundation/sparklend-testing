// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { Errors } from "aave-v3-core/contracts/protocol/libraries/helpers/Errors.sol";

import {
    MockReceiverBasic,
    MockReceiverReturnFalse,
    MockReceiverInsufficientApprove,
    MockReceiverInsufficientBalance,
    MockReceiverMintPremium
} from "test/mocks/MockReceiver.sol";

import { IERC20, SparkLendTestBase } from "./SparkLendTestBase.sol";

contract FlashLoanTestBase is SparkLendTestBase {

    address borrower = makeAddr("borrower");
    address supplier = makeAddr("supplier");

    address receiver;

    function setUp() public virtual override {
        super.setUp();

        receiver = address(new MockReceiverBasic(address(poolConfigurator), address(pool)));

        // Set up necessary conditions for success
        _supply(supplier, address(borrowAsset), 1000 ether);

        vm.prank(admin);
        poolConfigurator.setReserveFlashLoaning(address(borrowAsset), true);
    }

}

contract FlashLoanFailureTests is FlashLoanTestBase {

    function test_flashLoan_whenNotActive() public {
        // Avoid RESERVE_LIQUIDITY_NOT_ZERO error when deactivating
        _withdraw(supplier, address(borrowAsset), 1000 ether);

        vm.prank(admin);
        poolConfigurator.setReserveActive(address(borrowAsset), false);

        vm.expectRevert(bytes(Errors.RESERVE_INACTIVE));
        pool.flashLoan(receiver, address(borrowAsset), 1000 ether, new bytes(0), 0);
    }

    function test_flashLoan_whenPaused() public {
        vm.prank(admin);
        poolConfigurator.setReservePause(address(borrowAsset), true);

        vm.expectRevert(bytes(Errors.RESERVE_PAUSED));
        pool.flashLoan(receiver, address(borrowAsset), 1000 ether, new bytes(0), 0);
    }

    function test_flashLoan_whenFrozen() public {
        vm.prank(admin);
        poolConfigurator.setReserveFreeze(address(borrowAsset), true);

        pool.flashLoan(receiver, address(borrowAsset), 1000 ether, new bytes(0), 0);
    }

    function test_flashLoan_flashLoanNotEnabled() public {
        vm.prank(admin);
        poolConfigurator.setReserveFlashLoaning(address(borrowAsset), false);

        vm.expectRevert(bytes(Errors.FLASHLOAN_DISABLED));
        pool.flashLoan(receiver, address(borrowAsset), 1000 ether, new bytes(0), 0);
    }

    function test_flashLoan_insufficientLiquidityBoundary() public {
        vm.expectRevert(stdError.arithmeticError);
        pool.flashLoan(receiver, address(borrowAsset), 1000 ether + 1, new bytes(0), 0);

        pool.flashLoan(receiver, address(borrowAsset), 1000 ether, new bytes(0), 0);
    }

    function test_flashLoan_receiverReturnsFalse() public {
        receiver = address(new MockReceiverReturnFalse(address(poolConfigurator), address(pool)));

        vm.expectRevert(bytes(Errors.INVALID_FLASHLOAN_EXECUTOR_RETURN));
        pool.flashLoan(receiver, address(borrowAsset), 1000 ether, new bytes(0), 0);
    }

    function test_flashLoan_receiverInsufficientApprovalBoundary() public {
        receiver = address(new MockReceiverInsufficientApprove(address(poolConfigurator), address(pool)));

        vm.expectRevert(stdError.arithmeticError);
        pool.flashLoan(receiver, address(borrowAsset), 1000 ether, new bytes(0), 0);

        receiver = address(new MockReceiverBasic(address(poolConfigurator), address(pool)));

        pool.flashLoan(receiver, address(borrowAsset), 1000 ether, new bytes(0), 0);
    }

    function test_flashLoan_receiverInsufficientBalanceBoundary() public {
        receiver = address(new MockReceiverInsufficientBalance(address(poolConfigurator), address(pool)));

        vm.expectRevert(stdError.arithmeticError);
        pool.flashLoan(receiver, address(borrowAsset), 1000 ether, new bytes(0), 0);

        receiver = address(new MockReceiverBasic(address(poolConfigurator), address(pool)));

        pool.flashLoan(receiver, address(borrowAsset), 1000 ether, new bytes(0), 0);
    }

}
