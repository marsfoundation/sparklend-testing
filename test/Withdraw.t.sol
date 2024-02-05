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

}
