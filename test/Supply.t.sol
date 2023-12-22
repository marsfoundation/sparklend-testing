// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { Errors }  from "aave-v3-core/protocol/libraries/helpers/Errors.sol";
import { IAToken } from "aave-v3-core/protocol/tokenization/AToken.sol";

import {
    DefaultReserveInterestRateStrategy,
    IERC20,
    IReserveInterestRateStrategy,
    MockERC20,
    SparklendTestBase
} from "./SparklendTestBase.sol";

contract SupplyFailureTests is SparklendTestBase {

    address supplier = makeAddr("supplier");

    function test_supply_success_replaceThis() public {
        vm.startPrank(supplier);

        collateralAsset.mint(supplier, 1000 ether);
        collateralAsset.approve(address(pool), 1000 ether);
        pool.supply(address(collateralAsset), 1000 ether, supplier, 0);
    }

    function test_supply_whenAmountZero() public {
        vm.expectRevert(bytes(Errors.INVALID_AMOUNT));
        pool.supply(address(collateralAsset), 0, supplier, 0);
    }

    function test_supply_whenNotActive() public {
        vm.prank(admin);
        poolConfigurator.setReserveActive(address(collateralAsset), false);

        vm.expectRevert(bytes(Errors.RESERVE_INACTIVE));
        pool.supply(address(collateralAsset), 1000 ether, supplier, 0);
    }

    function test_supply_whenPaused() public {
        vm.prank(admin);
        poolConfigurator.setReservePause(address(collateralAsset), true);

        vm.expectRevert(bytes(Errors.RESERVE_PAUSED));
        pool.supply(address(collateralAsset), 1000 ether, supplier, 0);
    }

    function test_supply_whenFrozen() public {
        vm.prank(admin);
        poolConfigurator.setReserveFreeze(address(collateralAsset), true);

        vm.expectRevert(bytes(Errors.RESERVE_FROZEN));
        pool.supply(address(collateralAsset), 1000 ether, supplier, 0);
    }

    function test_supply_amountOverSupplyCapBoundary() public {
        vm.prank(admin);
        poolConfigurator.setSupplyCap(address(collateralAsset), 1000);

        // Set up for success case
        collateralAsset.mint(supplier, 1000 ether);

        vm.startPrank(supplier);

        collateralAsset.approve(address(pool), 1000 ether);

        // Boundary is 1 wei, not 1 ether even though supply cap is
        // using units without decimals.
        vm.expectRevert(bytes(Errors.SUPPLY_CAP_EXCEEDED));
        pool.supply(address(collateralAsset), 1000 ether + 1, supplier, 0);

        pool.supply(address(collateralAsset), 1000 ether, supplier, 0);
    }

    function test_supply_insufficientApproveBoundary() public {
        collateralAsset.mint(supplier, 1000 ether);

        vm.startPrank(supplier);

        collateralAsset.approve(address(pool), 1000 ether - 1);

        vm.expectRevert(stdError.arithmeticError);
        pool.supply(address(collateralAsset), 1000 ether, supplier, 0);

        collateralAsset.approve(address(pool), 1000 ether);

        pool.supply(address(collateralAsset), 1000 ether, supplier, 0);
    }

    function test_supply_insufficientBalanceBoundary() public {
        vm.startPrank(supplier);

        collateralAsset.approve(address(pool), 1000 ether);
        collateralAsset.mint(supplier, 1000 ether - 1);

        vm.expectRevert(stdError.arithmeticError);
        pool.supply(address(collateralAsset), 1000 ether, supplier, 0);

        collateralAsset.mint(supplier, 1);

        pool.supply(address(collateralAsset), 1000 ether, supplier, 0);
    }

    function test_supply_aTokenMintNotCalledByPool() public {
        address aToken = pool.getReserveData(address(collateralAsset)).aTokenAddress;

        vm.expectRevert(bytes(Errors.CALLER_MUST_BE_POOL));
        IAToken(aToken).mint(address(this), address(this), 1000 ether, 1e18);
    }

    function test_supply_aTokenMintScaledInvalidAmount() public {
        address aToken = pool.getReserveData(address(collateralAsset)).aTokenAddress;

        vm.prank(address(pool));
        vm.expectRevert(bytes(Errors.INVALID_MINT_AMOUNT));
        IAToken(aToken).mint(address(this), address(this), 0, 1e18);
    }

}

contract SupplyConcreteTests is SparklendTestBase {

    address supplier = makeAddr("supplier");

    // NOTE: Have to use storage for these values so they can be used across modifiers.
    address otherCollateral1;
    address otherCollateral2;

    function setUp() public override {
        super.setUp();

        collateralAsset.mint(supplier, 1000 ether);

        vm.prank(supplier);
        collateralAsset.approve(address(pool), 1000 ether);
    }

    modifier givenFirstSupply { _; }

    modifier givenDebtCeilingGtZero {
        vm.prank(admin);
        poolConfigurator.setDebtCeiling(address(collateralAsset), 1000);
        _;
    }

    modifier givenUserHasNoIsolatedCollateralRole { _; }

    modifier givenUserDoesHaveIsolatedCollateralRole {
        vm.prank(admin);
        aclManager.grantRole(keccak256('ISOLATED_COLLATERAL_SUPPLIER'), supplier);
        _;
    }

    modifier givenLtvIsZero { _; }

    modifier givenLtvIsNotZero {
        // Set LTV to 1%
        vm.prank(admin);
        poolConfigurator.configureReserveAsCollateral(address(collateralAsset), 100, 100, 100_01);
        _;
    }

    modifier whenUserIsNotUsingOtherCollateral { _; }

    modifier whenUserIsUsingOtherCollateral { _; }

    modifier whenUserIsUsingOneOtherCollateral {
        otherCollateral1 = _setUpNewCollateral();

        // NOTE: Have to set the debt ceiling to non-zero value here because once a user supplies
        //       with a zero debt ceiling it cannot be set, can be set to zero though.
        _setCollateralDebtCeiling(otherCollateral1, 1000);
        _supplyAndUseAsCollateral(otherCollateral1);
        _;
    }

    modifier givenOneOtherCollateralHasDebtCeilingGtZero {
        vm.prank(admin);
        poolConfigurator.setDebtCeiling(otherCollateral1, 1000);
        _;
    }

    modifier givenOneOtherCollateralHasZeroDebtCeiling {
        vm.prank(admin);
        poolConfigurator.setDebtCeiling(otherCollateral1, 0);
        _;
    }

    modifier whenUserIsUsingMultipleOtherCollaterals {
        otherCollateral1 = _setUpNewCollateral();
        otherCollateral2 = _setUpNewCollateral();

        _supplyAndUseAsCollateral(otherCollateral1);
        _supplyAndUseAsCollateral(otherCollateral2);
        _;
    }

    function test_supply_1()
        public
        givenFirstSupply
        givenDebtCeilingGtZero
        givenUserHasNoIsolatedCollateralRole
    {
        vm.prank(supplier);
        pool.supply(address(collateralAsset), 1000 ether, supplier, 0);
    }

    function test_supply_2()
        public
        givenFirstSupply
        givenDebtCeilingGtZero
        givenUserDoesHaveIsolatedCollateralRole
        givenLtvIsZero
    {
        vm.prank(supplier);
        pool.supply(address(collateralAsset), 1000 ether, supplier, 0);
    }

    function test_supply_5()
        public
        givenFirstSupply
        givenDebtCeilingGtZero
        givenUserDoesHaveIsolatedCollateralRole
        givenLtvIsNotZero
        whenUserIsNotUsingOtherCollateral
    {
        vm.prank(supplier);
        pool.supply(address(collateralAsset), 1000 ether, supplier, 0);
    }

    function test_supply_6()
        public
        givenFirstSupply
        givenDebtCeilingGtZero
        givenUserDoesHaveIsolatedCollateralRole
        givenLtvIsNotZero
        whenUserIsUsingOtherCollateral
        whenUserIsUsingOneOtherCollateral
        givenOneOtherCollateralHasDebtCeilingGtZero
    {
        vm.prank(supplier);
        pool.supply(address(collateralAsset), 1000 ether, supplier, 0);
    }

    function test_supply_7()
        public
        givenFirstSupply
        givenDebtCeilingGtZero
        givenUserDoesHaveIsolatedCollateralRole
        givenLtvIsNotZero
        whenUserIsUsingOtherCollateral
        whenUserIsUsingOneOtherCollateral
        givenOneOtherCollateralHasZeroDebtCeiling
    {
        vm.prank(supplier);
        pool.supply(address(collateralAsset), 1000 ether, supplier, 0);
    }

    function test_supply_8()
        public
        givenFirstSupply
        givenDebtCeilingGtZero
        givenUserDoesHaveIsolatedCollateralRole
        givenLtvIsNotZero
        whenUserIsUsingOtherCollateral
        whenUserIsUsingMultipleOtherCollaterals
    {
        vm.prank(supplier);
        pool.supply(address(collateralAsset), 1000 ether, supplier, 0);
    }

    /**********************************************************************************************/
    /*** Helper functions                                                                       ***/
    /**********************************************************************************************/

    function _setUpNewCollateral() internal returns (address newCollateralAsset) {
        IReserveInterestRateStrategy strategy
            = IReserveInterestRateStrategy(new DefaultReserveInterestRateStrategy({
                provider:                      poolAddressesProvider,
                optimalUsageRatio:             0.90e27,
                baseVariableBorrowRate:        0.05e27,
                variableRateSlope1:            0.02e27,
                variableRateSlope2:            0.3e27,
                stableRateSlope1:              0,
                stableRateSlope2:              0,
                baseStableRateOffset:          0,
                stableRateExcessOffset:        0,
                optimalStableToTotalDebtRatio: 0
            }));

        newCollateralAsset = address(new MockERC20("Collateral Asset", "COLL", 18));

        _initReserve(IERC20(newCollateralAsset), strategy);
        _setUpMockOracle(newCollateralAsset, int256(1e8));

        // Set LTV to 1%
        vm.prank(admin);
        poolConfigurator.configureReserveAsCollateral(newCollateralAsset, 100, 100, 100_01);
    }

    function _supplyAndUseAsCollateral(address newCollateralAsset) internal {
        vm.startPrank(supplier);
        MockERC20(newCollateralAsset).mint(supplier, 1000 ether);
        MockERC20(newCollateralAsset).approve(address(pool), 1000 ether);
        pool.supply(newCollateralAsset, 1000 ether, supplier, 0);
        pool.setUserUseReserveAsCollateral(newCollateralAsset, true);
        vm.stopPrank();
    }

    function _setCollateralDebtCeiling(address newCollateralAsset, uint256 ceiling) internal {
        vm.prank(admin);
        poolConfigurator.setDebtCeiling(newCollateralAsset, ceiling);
    }
}

