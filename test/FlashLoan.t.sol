// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { Errors } from "sparklend-v1-core/contracts/protocol/libraries/helpers/Errors.sol";

import {
    MockReceiverBasic,
    MockReceiverReturnFalse,
    MockReceiverInsufficientApprove,
    MockReceiverInsufficientBalance,
    MockReceiverMintPremium
} from "test/mocks/MockReceiver.sol";

import { SparkLendTestBase } from "./SparkLendTestBase.sol";

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

    function test_flashLoan_whenLengthAssetsDoesNotEqualLengthAmounts() public {
        address[] memory assets  = new address[](3);
        uint256[] memory amounts = new uint256[](2);
        uint256[] memory modes   = new uint256[](2);

        assets[0] = asset0;
        assets[1] = asset1;

        amounts[0] = 1;
        amounts[1] = 1;

        modes[0] = 0;
        modes[1] = 0;

        vm.expectRevert(bytes(Errors.INCONSISTENT_FLASHLOAN_PARAMS));
        pool.flashLoan(receiver, assets, amounts, modes, borrower, new bytes(0), 0);

        assets = new address[](1);  // Check less than case as well
        assets[0] = asset0;

        vm.expectRevert(bytes(Errors.INCONSISTENT_FLASHLOAN_PARAMS));
        pool.flashLoan(receiver, assets, amounts, modes, borrower, new bytes(0), 0);
    }

    function test_flashLoan_whenModesLengthLtAmounts() public {
        address[] memory assets  = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        uint256[] memory modes   = new uint256[](1);

        assets[0] = asset0;
        assets[1] = asset1;

        amounts[0] = 1;
        amounts[1] = 1;

        modes[0] = 0;

        vm.expectRevert(stdError.indexOOBError);
        pool.flashLoan(receiver, assets, amounts, modes, borrower, new bytes(0), 0);

        // Demonstrate modes can be greater than
        modes = new uint256[](3);
        modes[0] = 0;
        modes[1] = 0;
        modes[2] = 0;

        pool.flashLoan(receiver, assets, amounts, modes, borrower, new bytes(0), 0);
    }

    function test_flashLoan_whenNotActive_asset0() public {
        // Avoid RESERVE_LIQUIDITY_NOT_ZERO error when deactivating
        _withdraw(supplier, asset0, 1000 ether);

        vm.prank(admin);
        poolConfigurator.setReserveActive(asset0, false);

        vm.expectRevert(bytes(Errors.RESERVE_INACTIVE));
        _callFlashLoan(1000 ether, 1000 ether, borrower);
    }

    function test_flashLoan_whenNotActive_asset1() public {
        // Avoid RESERVE_LIQUIDITY_NOT_ZERO error when deactivating
        _withdraw(supplier, asset1, 1000 ether);

        vm.prank(admin);
        poolConfigurator.setReserveActive(asset1, false);

        vm.expectRevert(bytes(Errors.RESERVE_INACTIVE));
        _callFlashLoan(1000 ether, 1000 ether, borrower);
    }

    function test_flashLoan_whenPaused_asset0() public {
        vm.prank(admin);
        poolConfigurator.setReservePause(asset0, true);

        vm.expectRevert(bytes(Errors.RESERVE_PAUSED));
        _callFlashLoan(1000 ether, 1000 ether, borrower);
    }

    function test_flashLoan_whenPaused_asset1() public {
        vm.prank(admin);
        poolConfigurator.setReservePause(asset1, true);

        vm.expectRevert(bytes(Errors.RESERVE_PAUSED));
        _callFlashLoan(1000 ether, 1000 ether, borrower);
    }

    function test_flashLoan_whenFrozen_asset0() public {
        vm.prank(admin);
        poolConfigurator.setReserveFreeze(asset0, true);

        _callFlashLoan(1000 ether, 1000 ether, borrower);
    }

    function test_flashLoan_whenFrozen_asset1() public {
        vm.prank(admin);
        poolConfigurator.setReserveFreeze(asset1, true);

        _callFlashLoan(1000 ether, 1000 ether, borrower);
    }

    function test_flashLoan_flashLoanNotEnabled_asset0() public {
        vm.prank(admin);
        poolConfigurator.setReserveFlashLoaning(asset0, false);

        vm.expectRevert(bytes(Errors.FLASHLOAN_DISABLED));
        _callFlashLoan(1000 ether, 1000 ether, borrower);
    }

    function test_flashLoan_flashLoanNotEnabled_asset1() public {
        vm.prank(admin);
        poolConfigurator.setReserveFlashLoaning(asset1, false);

        vm.expectRevert(bytes(Errors.FLASHLOAN_DISABLED));
        _callFlashLoan(1000 ether, 1000 ether, borrower);
    }

    function test_flashLoan_insufficientLiquidityBoundary_asset0() public {
        vm.expectRevert(stdError.arithmeticError);
        _callFlashLoan(1000 ether + 1, 1000 ether, borrower);

        _callFlashLoan(1000 ether, 1000 ether, borrower);
    }

    function test_flashLoan_insufficientLiquidityBoundary_asset1() public {
        vm.expectRevert(stdError.arithmeticError);
        _callFlashLoan(1000 ether, 1000 ether + 1, borrower);

        _callFlashLoan(1000 ether, 1000 ether, borrower);
    }

    function test_flashLoan_receiverReturnsFalse() public {
        receiver = address(new MockReceiverReturnFalse(address(poolConfigurator), address(pool)));

        vm.expectRevert(bytes(Errors.INVALID_FLASHLOAN_EXECUTOR_RETURN));
        _callFlashLoan(1000 ether, 1000 ether, borrower);
    }

    function test_flashLoan_receiverInsufficientApprovalBoundary_asset0() public {
        receiver = address(new MockReceiverInsufficientApprove(address(poolConfigurator), address(pool), asset0));

        vm.expectRevert(stdError.arithmeticError);
        _callFlashLoan(1000 ether, 1000 ether, borrower);

        receiver = address(new MockReceiverBasic(address(poolConfigurator), address(pool)));

        _callFlashLoan(1000 ether, 1000 ether, borrower);
    }

    function test_flashLoan_receiverInsufficientApprovalBoundary_asset1() public {
        receiver = address(new MockReceiverInsufficientApprove(address(poolConfigurator), address(pool), asset1));

        vm.expectRevert(stdError.arithmeticError);
        _callFlashLoan(1000 ether, 1000 ether, borrower);

        receiver = address(new MockReceiverBasic(address(poolConfigurator), address(pool)));

        _callFlashLoan(1000 ether, 1000 ether, borrower);
    }

    function test_flashLoan_receiverInsufficientBalanceBoundary_asset0() public {
        receiver = address(new MockReceiverInsufficientBalance(address(poolConfigurator), address(pool), asset0));

        vm.expectRevert(stdError.arithmeticError);
        _callFlashLoan(1000 ether, 1000 ether, borrower);

        receiver = address(new MockReceiverBasic(address(poolConfigurator), address(pool)));

        _callFlashLoan(1000 ether, 1000 ether, borrower);
    }

    function test_flashLoan_receiverInsufficientBalanceBoundary_asset1() public {
        receiver = address(new MockReceiverInsufficientBalance(address(poolConfigurator), address(pool), asset1));

        vm.expectRevert(stdError.arithmeticError);
        _callFlashLoan(1000 ether, 1000 ether, borrower);

        receiver = address(new MockReceiverBasic(address(poolConfigurator), address(pool)));

        _callFlashLoan(1000 ether, 1000 ether, borrower);
    }

    function test_flashLoan_userTriesToFlashLoanIntoBorrow_asset0() public {
        address[] memory assets  = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        uint256[] memory modes   = new uint256[](2);

        assets[0] = asset0;
        assets[1] = asset1;

        amounts[0] = 1000 ether;
        amounts[1] = 1000 ether;

        modes[0] = 1;
        modes[1] = 0;

        vm.expectRevert("FLASHLOAN_INTO_BORROW_DEPRECATED");
        pool.flashLoan(receiver, assets, amounts, modes, borrower, new bytes(0), 0);
    }

    function test_flashLoan_userTriesToFlashLoanIntoBorrow_asset1() public {
        address[] memory assets  = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        uint256[] memory modes   = new uint256[](2);

        assets[0] = asset0;
        assets[1] = asset1;

        amounts[0] = 1000 ether;
        amounts[1] = 1000 ether;

        modes[0] = 0;
        modes[1] = 1;

        vm.expectRevert("FLASHLOAN_INTO_BORROW_DEPRECATED");
        pool.flashLoan(receiver, assets, amounts, modes, borrower, new bytes(0), 0);
    }

}
