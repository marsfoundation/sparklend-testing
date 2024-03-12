// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { UserConfiguration } from "aave-v3-core/contracts/protocol/libraries/configuration/UserConfiguration.sol";
import { Errors }            from "aave-v3-core/contracts/protocol/libraries/helpers/Errors.sol";
import { DataTypes }         from "aave-v3-core/contracts/protocol/libraries/types/DataTypes.sol";

import {
    MockReceiverBasic,
    MockReceiverReturnFalse,
    MockReceiverInsufficientApprove,
    MockReceiverInsufficientBalance
} from "test/mocks/MockReceiver.sol";

import { IERC20, SparkLendTestBase } from "./SparkLendTestBase.sol";

contract FlashLoanSimpleTestBase is SparkLendTestBase {

    address borrower = makeAddr("borrower");

    address receiver;

    function setUp() public virtual override {
        super.setUp();

        receiver = address(new MockReceiverBasic(address(poolConfigurator), address(pool)));
    }

}

contract FlashLoanSimpleFailureTests is FlashLoanSimpleTestBase {

    function setUp() public virtual override {
        super.setUp();

        receiver = address(new MockReceiverBasic(address(poolConfigurator), address(pool)));

        // Set up necessary conditions for success
        _supply(makeAddr("supplier"), address(borrowAsset), 1000 ether);

        vm.prank(admin);
        poolConfigurator.setReserveFlashLoaning(address(borrowAsset), true);
    }

    function test_flashLoanSimple_whenNotActive() public {
        // Avoid RESERVE_LIQUIDITY_NOT_ZERO error when deactivating
        _withdraw(makeAddr("supplier"), address(borrowAsset), 1000 ether);

        vm.prank(admin);
        poolConfigurator.setReserveActive(address(borrowAsset), false);

        vm.expectRevert(bytes(Errors.RESERVE_INACTIVE));
        pool.flashLoanSimple(receiver, address(borrowAsset), 1000 ether, new bytes(0), 0);
    }

    function test_flashLoanSimple_whenPaused() public {
        vm.prank(admin);
        poolConfigurator.setReservePause(address(borrowAsset), true);

        vm.expectRevert(bytes(Errors.RESERVE_PAUSED));
        pool.flashLoanSimple(receiver, address(borrowAsset), 1000 ether, new bytes(0), 0);
    }

    function test_flashLoanSimple_whenFrozen() public {
        vm.prank(admin);
        poolConfigurator.setReserveFreeze(address(borrowAsset), true);

        pool.flashLoanSimple(receiver, address(borrowAsset), 1000 ether, new bytes(0), 0);
    }

    function test_flashLoanSimple_flashLoanNotEnabled() public {
        vm.prank(admin);
        poolConfigurator.setReserveFlashLoaning(address(borrowAsset), false);

        vm.expectRevert(bytes(Errors.FLASHLOAN_DISABLED));
        pool.flashLoanSimple(receiver, address(borrowAsset), 1000 ether, new bytes(0), 0);
    }

    function test_flashLoanSimple_insufficientLiquidityBoundary() public {
        vm.expectRevert(stdError.arithmeticError);
        pool.flashLoanSimple(receiver, address(borrowAsset), 1000 ether + 1, new bytes(0), 0);

        pool.flashLoanSimple(receiver, address(borrowAsset), 1000 ether, new bytes(0), 0);
    }

    function test_flashLoanSimple_receiverReturnsFalse() public {
        receiver = address(new MockReceiverReturnFalse(address(poolConfigurator), address(pool)));

        vm.expectRevert(bytes(Errors.INVALID_FLASHLOAN_EXECUTOR_RETURN));
        pool.flashLoanSimple(receiver, address(borrowAsset), 1000 ether, new bytes(0), 0);
    }

    function test_flashLoanSimple_receiverInsufficientApprovalBoundary() public {
        receiver = address(new MockReceiverInsufficientApprove(address(poolConfigurator), address(pool)));

        vm.expectRevert(stdError.arithmeticError);
        pool.flashLoanSimple(receiver, address(borrowAsset), 1000 ether, new bytes(0), 0);

        receiver = address(new MockReceiverBasic(address(poolConfigurator), address(pool)));

        pool.flashLoanSimple(receiver, address(borrowAsset), 1000 ether, new bytes(0), 0);
    }

    function test_flashLoanSimple_receiverInsufficientBalanceBoundary() public {
        receiver = address(new MockReceiverInsufficientBalance(address(poolConfigurator), address(pool)));

        vm.expectRevert(stdError.arithmeticError);
        pool.flashLoanSimple(receiver, address(borrowAsset), 1000 ether, new bytes(0), 0);

        receiver = address(new MockReceiverBasic(address(poolConfigurator), address(pool)));

        pool.flashLoanSimple(receiver, address(borrowAsset), 1000 ether, new bytes(0), 0);
    }

}
