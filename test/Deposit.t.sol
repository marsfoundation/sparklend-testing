// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import { SupplyFailureTests, SupplyConcreteTests } from "./Supply.t.sol";

// Prove equivalence of deposit and supply
// NOTE: `deposit` does not have a .tree file because of this
contract DepositFailureTests is SupplyFailureTests {

    function _callSupply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode)
        internal override
    {
        vm.prank(supplier);
        pool.deposit(asset, amount, onBehalfOf, referralCode);
    }

}

contract DepositConcreteTests is SupplyConcreteTests {

    function _callSupply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode)
        internal override
    {
        vm.prank(supplier);
        pool.deposit(asset, amount, onBehalfOf, referralCode);
    }

}

