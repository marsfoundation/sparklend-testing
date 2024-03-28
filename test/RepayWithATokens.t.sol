// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { Errors } from "aave-v3-core/contracts/protocol/libraries/helpers/Errors.sol";

import { RepayFailureTests, RepayConcreteTests } from "./Repay.t.sol";

import { SparkLendTestBase } from "./SparkLendTestBase.sol";

contract RepayTestBase is SparkLendTestBase {

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
        _borrow(borrower, address(borrowAsset), 500 ether);
    }

    function _callRepay(address asset, uint256 amount, uint256 rateMode)
        internal virtual
    {
        vm.prank(borrower);
        pool.repayWithATokens(asset, amount, rateMode);
    }

}

contract RepayWithATokensFailureTests is RepayFailureTests {

    function setUp() public virtual override {
        super.setUp();
        _supply(borrower, address(borrowAsset), 500 ether);  // Get aTokens
    }

    function _callRepay(address asset, uint256 amount, uint256 rateMode, address onBehalfOf)
        internal override
    {
        vm.prank(borrower);
        pool.repayWithATokens(asset, amount, rateMode);
    }

    function test_repay_insufficientApprovalBoundary() public override {}
    function test_repay_insufficientBalanceBoundary() public override {}
    function test_repay_whenAmountIsUint256MaxAndUserNotOwner() public override {}

    function test_repay_whenNotActive() public override {
        // Undo supply so reserve can be set to inactive
        _withdraw(borrower, address(borrowAsset), 500 ether);

        super.test_repay_whenNotActive();
    }

}
