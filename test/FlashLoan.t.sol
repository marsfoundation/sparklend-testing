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

    // Renaming assets for this test for easier comprehension
    address asset0;
    address asset1;

    function setUp() public virtual override {
        super.setUp();

        receiver = address(new MockReceiverBasic(address(poolConfigurator), address(pool)));

        asset0 = address(borrowAsset);
        asset1 = address(collateralAsset);

        // Set up necessary conditions for success
        _supply(supplier, asset0, 1000 ether);
        _supply(supplier, asset1, 1000 ether);

        vm.startPrank(admin);
        poolConfigurator.setReserveFlashLoaning(asset0, true);
        poolConfigurator.setReserveFlashLoaning(asset1, true);
        vm.stopPrank();
    }

    function _callFlashLoan(uint256 amount0, uint256 amount1, address onBehalfOf) internal {
        address[] memory assets  = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        uint256[] memory modes   = new uint256[](2);

        assets[0] = asset0;
        assets[1] = asset1;

        amounts[0] = amount0;
        amounts[1] = amount1;

        modes[0] = 0;
        modes[1] = 0;

        pool.flashLoan(receiver, assets, amounts, modes, onBehalfOf, new bytes(0), 0);
    }

}

contract FlashLoanFailureTests is FlashLoanTestBase {

    function test_flashLoan_whenNotActive() public {
        // Avoid RESERVE_LIQUIDITY_NOT_ZERO error when deactivating
        _withdraw(supplier, asset0, 1000 ether);

        vm.prank(admin);
        poolConfigurator.setReserveActive(asset0, false);

        vm.expectRevert(bytes(Errors.RESERVE_INACTIVE));
        _callFlashLoan(1000 ether, 1000 ether, borrower);
    }

    function test_flashLoan_whenPaused() public {
        vm.prank(admin);
        poolConfigurator.setReservePause(asset0, true);

        vm.expectRevert(bytes(Errors.RESERVE_PAUSED));
        _callFlashLoan(1000 ether, 1000 ether, borrower);
    }

    function test_flashLoan_whenFrozen() public {
        vm.prank(admin);
        poolConfigurator.setReserveFreeze(asset0, true);

        _callFlashLoan(1000 ether, 1000 ether, borrower);
    }

    function test_flashLoan_flashLoanNotEnabled() public {
        vm.prank(admin);
        poolConfigurator.setReserveFlashLoaning(asset0, false);

        vm.expectRevert(bytes(Errors.FLASHLOAN_DISABLED));
        _callFlashLoan(1000 ether, 1000 ether, borrower);
    }

    function test_flashLoan_insufficientLiquidityBoundary() public {
        vm.expectRevert(stdError.arithmeticError);
        _callFlashLoan(1000 ether, 1000 ether + 1, borrower);

        _callFlashLoan(1000 ether, 1000 ether, borrower);
    }

    function test_flashLoan_receiverReturnsFalse() public {
        receiver = address(new MockReceiverReturnFalse(address(poolConfigurator), address(pool)));

        vm.expectRevert(bytes(Errors.INVALID_FLASHLOAN_EXECUTOR_RETURN));
        _callFlashLoan(1000 ether, 1000 ether, borrower);
    }

    function test_flashLoan_receiverInsufficientApprovalBoundary() public {
        receiver = address(new MockReceiverInsufficientApprove(address(poolConfigurator), address(pool), asset0));

        vm.expectRevert(stdError.arithmeticError);
        _callFlashLoan(1000 ether, 1000 ether, borrower);

        receiver = address(new MockReceiverBasic(address(poolConfigurator), address(pool)));

        _callFlashLoan(1000 ether, 1000 ether, borrower);
    }

    function test_flashLoan_receiverInsufficientBalanceBoundary() public {
        receiver = address(new MockReceiverInsufficientBalance(address(poolConfigurator), address(pool), asset0));

        vm.expectRevert(stdError.arithmeticError);
        _callFlashLoan(1000 ether, 1000 ether, borrower);

        receiver = address(new MockReceiverBasic(address(poolConfigurator), address(pool)));

        _callFlashLoan(1000 ether, 1000 ether, borrower);
    }

}
