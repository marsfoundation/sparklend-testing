// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import { SparklendTestBase } from "./SparklendTestBase.sol";

contract SupplyTests is SparklendTestBase {

    address supplier = makeAddr("supplier");

    function test_supply() public {
        uint256 amount = 1000 ether;

        collateralAsset.mint(supplier, 1000 ether);

        vm.startPrank(supplier);
        collateralAsset.approve(address(pool), 1000 ether);
        pool.supply(address(collateralAsset), amount, supplier, 0);
    }

}
