// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import { Errors } from "sparklend-v1-core/contracts/protocol/libraries/helpers/Errors.sol";

import { SparkLendTestBase } from "test/SparkLendTestBase.sol";

contract ACLTests is SparkLendTestBase {

    address POOL_ADMIN;

    function setUp() public override {
        super.setUp();
        
        POOL_ADMIN = admin;
    }

    function test_rescueTokens() public {
        vm.expectRevert(bytes(Errors.CALLER_NOT_POOL_ADMIN));
        pool.rescueTokens(address(borrowAsset), address(this), 100);

        vm.prank(POOL_ADMIN);
        pool.rescueTokens(address(borrowAsset), address(this), 100);
    }

}
