// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { Errors } from "aave-v3-core/contracts/protocol/libraries/helpers/Errors.sol";

import { RepayFailureTests, RepayConcreteTests } from "./Repay.t.sol";

// Prove equivalence of repayWithPermit and repay
// NOTE: `repayWithPermit` does not have a .tree file because of this
// NOTE: Some tests are overridden because of permit specific logic
contract RepayWithPermitFailureTests is RepayFailureTests {

    uint256 borrowerSk = 1;

    uint256 nonce;  // Nonce in storage to be used over the course of tests

    uint8   permitV;
    bytes32 permitR;
    bytes32 permitS;

    function _getValidPermitSignature(uint256 amount) internal {
        ( permitV, permitR, permitS ) = _getValidPermitSignature(
            address(borrowAsset),
            borrower,
            address(pool),
            amount,
            nonce,
            block.timestamp,
            borrowerSk
        );
    }

    function setUp() public virtual override {
        borrower = vm.addr(borrowerSk);  // Overwrite borrower address before running other setUp

        super.setUp();

        vm.label(borrower, "borrower");

        // NOTE: Using these so that no external calls are made during error assertions
        _getValidPermitSignature(500 ether);
    }

    function _callRepay(
        address asset,
        uint256 amount,
        uint256 rateMode,
        address onBehalfOf
    )
        internal override
    {
        vm.prank(borrower);
        pool.repayWithPermit(
            asset,
            amount,
            rateMode,
            onBehalfOf,
            block.timestamp,
            permitV,
            permitR,
            permitS
        );
    }

    function test_repay_whenAmountZero() public override {
        _getValidPermitSignature(0);
        vm.expectRevert(bytes(Errors.INVALID_AMOUNT));
        _callRepay(address(borrowAsset), 0, 2, borrower);
    }

    function test_repay_whenAmountIsUint256MaxAndUserNotOwner() public override {
        _getValidPermitSignature(type(uint256).max);
        vm.expectRevert(bytes(Errors.NO_EXPLICIT_AMOUNT_TO_REPAY_ON_BEHALF));
        _callRepay(address(borrowAsset), type(uint256).max, 2, makeAddr("user"));
    }

    // Skipping test as it does not apply
    function test_repay_insufficientApprovalBoundary() public override {}

    // Analogous test to insufficientApprovalBoundary
    function test_repayWithPermit_permitAmountMismatch() public {
        deal(address(borrowAsset), borrower, 500 ether);

        _getValidPermitSignature(500 ether - 1);

        vm.expectRevert();
        _callRepay(address(borrowAsset), 500 ether, 2, borrower);
    }

    function test_repay_insufficientBalanceBoundary() public override {
        vm.startPrank(borrower);

        _getValidPermitSignature(500 ether);

        deal(address(borrowAsset), borrower, 500 ether - 1);

        vm.stopPrank();

        vm.expectRevert(stdError.arithmeticError);
        _callRepay(address(borrowAsset), 500 ether, 2, borrower);

        deal(address(borrowAsset), borrower, 500 ether);

        _callRepay(address(borrowAsset), 500 ether, 2, borrower);
    }

}

contract RepayWithPermitConcreteTests is RepayConcreteTests {

    uint256 borrowerSk = 1;

    uint256 nonce;  // Nonce in storage to be used over the course of tests

    function setUp() public virtual override {
        borrower = vm.addr(borrowerSk);  // Overwrite borrower address before running other setUp

        super.setUp();

        vm.label(borrower, "borrower");
    }

    function _callRepay(
        address asset,
        uint256 amount,
        uint256 rateMode,
        address onBehalfOf
    )
        internal override
    {
        // Explicitly set the approval to zero before the repayWithPermit is called.
        // In the other tests, the approval state changes, in order to make this work we can
        // set the approval to zero on every call and permit instead.
        vm.prank(borrower);
        borrowAsset.approve(address(pool), 0);

        ( uint8 permitV, bytes32 permitR, bytes32 permitS ) = _getValidPermitSignature(
            address(borrowAsset),
            onBehalfOf,
            address(pool),
            amount,
            nonce++,
            block.timestamp,
            borrowerSk
        );

        vm.prank(borrower);
        pool.repayWithPermit(
            asset,
            amount,
            rateMode,
            onBehalfOf,
            block.timestamp,
            permitV,
            permitR,
            permitS
        );
    }

}
