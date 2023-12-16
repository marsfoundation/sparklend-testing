// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import { DefaultReserveInterestRateStrategy } from "lib/aave-v3-core/contracts/protocol/pool/DefaultReserveInterestRateStrategy.sol";
import { ACLManager } from "lib/aave-v3-core/contracts/protocol/configuration/ACLManager.sol";
import { Pool } from "lib/aave-v3-core/contracts/protocol/pool/Pool.sol";

contract SparklendTestBase is Test {

    function setUp() public virtual {

    }

    function test_example() public virtual {

    }
}
