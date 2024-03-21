// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { IPool } from "aave-v3-core/contracts/interfaces/IPool.sol";

import "sparklend-address-registry/Ethereum.sol";

contract IntegrationTestBase is Test {

    IPool constant pool = IPool(Ethereum.POOL);

    function setUp() public {

    }

    function test_integration() public {
        console.log(Ethereum.POOL);
    }
}

