// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { Errors } from "sparklend-v1-core/contracts/protocol/libraries/helpers/Errors.sol";

import { SupplyFailureTests, SupplyConcreteTests } from "./Supply.t.sol";

// Prove equivalence of supplyWithPermit and supply
// NOTE: `supplyWithPermit` does not have a .tree file because of this
// NOTE: Some tests are overridden because of permit specific logic
contract SupplyWithPermitFailureTests is SupplyFailureTests {

    uint256 supplierSk = 1;

    uint256 nonce;  // Nonce in storage to be used over the course of tests

    uint8   permitV;
    bytes32 permitR;
    bytes32 permitS;

    function _getValidPermitSignature(uint256 amount) internal {
        ( permitV, permitR, permitS ) = _getValidPermitSignature(
            address(collateralAsset),
            supplier,
            address(pool),
            amount,
            nonce,
            block.timestamp,
            supplierSk
        );
    }

    function setUp() public virtual override {
        supplier = vm.addr(supplierSk);  // Overwrite supplier address before running other setUp

        super.setUp();

        vm.label(supplier, "supplier");

        // NOTE: Using these so that no external calls are made during error assertions
        _getValidPermitSignature(1000 ether);
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

    function test_supply_whenAmountZero() public override {
        _getValidPermitSignature(0);

        vm.expectRevert(bytes(Errors.INVALID_AMOUNT));
        _callSupply(address(collateralAsset), 0, supplier, 0);
    }

    function test_supply_amountOverSupplyCapBoundary() public override {
        vm.prank(admin);
        poolConfigurator.setSupplyCap(address(collateralAsset), 1000);

        // Mint enough funds for the 1000 ether supply to succeed
        collateralAsset.mint(supplier, 1000 ether);

        vm.prank(supplier);
        collateralAsset.approve(address(pool), 1000 ether);

        _getValidPermitSignature(1000 ether + 1);

        // Boundary is 1 wei, not 1 ether even though supply cap is
        // using units without decimals.
        vm.expectRevert(bytes(Errors.SUPPLY_CAP_EXCEEDED));
        _callSupply(address(collateralAsset), 1000 ether + 1, supplier, 0);

        _getValidPermitSignature(1000 ether);

        _callSupply(address(collateralAsset), 1000 ether, supplier, 0);
    }

    // Skipping test as it does not apply
    function test_supply_insufficientApproveBoundary() public override {}

    function test_supplyWithPermit_permitAmountMismatch() public {
        collateralAsset.mint(supplier, 1000 ether);

        _getValidPermitSignature(1000 ether - 1);

        vm.expectRevert();
        _callSupply(address(collateralAsset), 1000 ether, supplier, 0);
    }

    function test_supply_insufficientBalanceBoundary() public override {
        vm.startPrank(supplier);

        _getValidPermitSignature(1000 ether);

        collateralAsset.mint(supplier, 1000 ether - 1);

        vm.stopPrank();

        vm.expectRevert(stdError.arithmeticError);
        _callSupply(address(collateralAsset), 1000 ether, supplier, 0);

        collateralAsset.mint(supplier, 1);

        _callSupply(address(collateralAsset), 1000 ether, supplier, 0);
    }

    function test_supply_aTokenMintScaledInvalidAmount() public override {
        _initCollateral({
            asset:                address(borrowAsset),
            ltv:                  50_00,
            liquidationThreshold: 60_00,
            liquidationBonus:     100_01
        });

        vm.prank(admin);
        poolConfigurator.setReserveBorrowing(address(collateralAsset), true);

        address user = makeAddr("user");

        // Accrue enough interest against the collateralAsset that the aToken
        // will round down to zero on a supply of 1 because of the index
        _supply(user, address(collateralAsset), 500 ether);
        _supply(user, address(borrowAsset),     1000 ether);
        _borrow(user, address(collateralAsset), 500 ether);
        vm.warp(10_000 days);

        vm.startPrank(supplier);

        _getValidPermitSignature(1);
        collateralAsset.mint(supplier, 1);

        vm.stopPrank();

        vm.expectRevert(bytes(Errors.INVALID_MINT_AMOUNT));
        _callSupply(address(collateralAsset), 1, supplier, 0);
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

