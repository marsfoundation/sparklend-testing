// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import { SparklendTestBase } from "./SparklendTestBase.sol";

contract SupplyTests is SparklendTestBase {

    address supplier = makeAddr("supplier");

    function test_supply() public {
        borrowAsset.mint(address(this), 1000 ether);
    }

}
