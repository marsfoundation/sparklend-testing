// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { SupplyFailureTests, SupplyConcreteTests } from "./Supply.t.sol";


// Prove equivalence of supplyWithPermit and supply
// NOTE: `supplyWithPermit` does not have a .tree file because of this
contract SupplyWithPermitFailureTests is SupplyFailureTests {

    uint256 supplierSk = 1;

    uint256 nonce;  // Nonce in storage to be used over the course of tests

    uint8   permitV;
    bytes32 permitR;
    bytes32 permitS;

    function setUp() public virtual override {
        supplier = vm.addr(supplierSk);  // Overwrite supplier address before running other setUp

        super.setUp();

        vm.label(supplier, "supplier");

        // NOTE: Using these so that no external calls are made during error assertions
        ( permitV, permitR, permitS ) = _getValidPermitSignature(
            address(collateralAsset),
            supplier,
            address(pool),
            1000 ether,
            0,
            block.timestamp,
            supplierSk
        );
    }

    function _callSupply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode)
        internal override
    {
        vm.prank(supplier);
        pool.supplyWithPermit(
            asset,
            amount,
            onBehalfOf,
            referralCode,
            block.timestamp,
            permitV,
            permitR,
            permitS
        );
    }

}

contract SupplyWithPermitConcreteTests is SupplyConcreteTests {

    uint256 supplierSk = 1;

    uint256 nonce;  // Nonce in storage to be used over the course of tests

    function setUp() public virtual override {
        supplier = vm.addr(supplierSk);  // Overwrite supplier address before running other setUp

        super.setUp();

        vm.label(supplier, "supplier");
    }

    function _callSupply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode)
        internal override
    {
        // Explicitly set the approval to zero before the supplyWithPermit is called.
        // In the other tests, the approval state changes, in order to make this work we can
        // set the approval to zero on every call and permit instead.
        vm.prank(supplier);
        collateralAsset.approve(address(pool), 0);

        ( uint8 permitV, bytes32 permitR, bytes32 permitS ) = _getValidPermitSignature(
            address(collateralAsset),
            onBehalfOf,
            address(pool),
            amount,
            nonce++,
            block.timestamp,
            supplierSk
        );

        vm.prank(supplier);
        pool.supplyWithPermit(
            asset,
            amount,
            onBehalfOf,
            referralCode,
            block.timestamp,
            permitV,
            permitR,
            permitS
        );
    }

}

