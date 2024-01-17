// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { UserConfiguration } from "aave-v3-core/contracts/protocol/libraries/configuration/UserConfiguration.sol";
import { Errors }            from "aave-v3-core/contracts/protocol/libraries/helpers/Errors.sol";
import { DataTypes }         from "aave-v3-core/contracts/protocol/libraries/types/DataTypes.sol";
import { IAToken }           from "aave-v3-core/contracts/protocol/tokenization/AToken.sol";

import {
    IERC20,
    IReserveInterestRateStrategy,
    MockERC20,
    SparkLendTestBase
} from "test/SparkLendTestBase.sol";

contract SupplyTestBase is SparkLendTestBase {

    address supplier = makeAddr("supplier");

    uint16 reserveId;

    IAToken aToken;

    function setUp() public virtual override {
        super.setUp();

        reserveId = pool.getReserveData(address(collateralAsset)).id;
        aToken    = IAToken(pool.getReserveData(address(collateralAsset)).aTokenAddress);

        vm.label(address(collateralAsset), "collateralAsset");
        vm.label(address(aToken),          "aToken");
        vm.label(address(pool),            "pool");
    }

}

contract SupplyFailureTests is SupplyTestBase {

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
        vm.expectRevert(bytes(Errors.CALLER_MUST_BE_POOL));
        aToken.mint(address(this), address(this), 1000 ether, 1e18);
    }

    function test_supply_aTokenMintScaledInvalidAmount() public {
        vm.prank(address(pool));
        vm.expectRevert(bytes(Errors.INVALID_MINT_AMOUNT));
        aToken.mint(address(this), address(this), 0, 1e18);
    }

}

contract SupplyConcreteTests is SupplyTestBase {

    using UserConfiguration for DataTypes.UserConfigurationMap;

    // NOTE: Have to use storage for these values so they can be used across modifiers.
    address otherCollateral1;
    address otherCollateral2;

    function setUp() public override {
        super.setUp();

        collateralAsset.mint(supplier, 1000 ether);

        vm.prank(supplier);
        collateralAsset.approve(address(pool), 1000 ether);
    }

    /**********************************************************************************************/
    /*** BTT modifiers                                                                          ***/
    /**********************************************************************************************/

    modifier givenFirstSupply { _; }

    modifier givenNotFirstSupply {
        _supply(makeAddr("new-user"), address(collateralAsset), 500 ether);
        _;
    }

    modifier givenDebtCeilingGtZero {
        vm.prank(admin);
        poolConfigurator.setDebtCeiling(address(collateralAsset), 1000);
        _;
    }

    modifier givenZeroDebtCeiling { _; }

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
        _supplyAndUseAsCollateral(supplier, otherCollateral1, 1000 ether);
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

        _supplyAndUseAsCollateral(supplier, otherCollateral1, 1000 ether);
        _supplyAndUseAsCollateral(supplier, otherCollateral2, 1000 ether);
        _;
    }

    modifier givenNoTimeHasPassedAfterSupply { _; }

    modifier givenSomeTimeHasPassedAfterSupply() {
        vm.warp(1000 seconds);
        _;
    }

    modifier givenNoActiveBorrow { _; }

    modifier givenActiveBorrow {
        // Allow borrowAsset to be collateral to demo collateralAsset accruing interest
        _initCollateral({
            asset:                address(borrowAsset),
            ltv:                  5000,
            liquidationThreshold: 6000,
            liquidationBonus:     100_01
        });

        vm.prank(admin);
        poolConfigurator.setReserveBorrowing(address(collateralAsset), true);

        address borrower = makeAddr("borrower");
        _supplyAndUseAsCollateral(borrower, address(borrowAsset), 1000 ether);
        _borrow(borrower, address(collateralAsset), 100 ether);
        _;
    }

    modifier givenNoTimeHasPassedAfterBorrow { _; }

    modifier givenSomeTimeHasPassedAfterBorrow() {
        vm.warp(1000 seconds);
        _;
    }

    /**********************************************************************************************/
    /*** BTT tests                                                                              ***/
    /**********************************************************************************************/

    function test_supply_01()
        public
        givenFirstSupply
        givenDebtCeilingGtZero
        givenUserHasNoIsolatedCollateralRole
    {
        _noAutomaticCollateralSupplyTest();
    }

    function test_supply_02()
        public
        givenFirstSupply
        givenDebtCeilingGtZero
        givenUserDoesHaveIsolatedCollateralRole
        givenLtvIsZero
    {
        _noAutomaticCollateralSupplyTest();
    }

    function test_supply_03()
        public
        givenFirstSupply
        givenDebtCeilingGtZero
        givenUserDoesHaveIsolatedCollateralRole
        givenLtvIsNotZero
        whenUserIsNotUsingOtherCollateral
    {
        _automaticCollateralSupplyTest();
    }

    function test_supply_04()
        public
        givenFirstSupply
        givenDebtCeilingGtZero
        givenUserDoesHaveIsolatedCollateralRole
        givenLtvIsNotZero
        whenUserIsUsingOtherCollateral
        whenUserIsUsingOneOtherCollateral
        givenOneOtherCollateralHasDebtCeilingGtZero
    {
        _noAutomaticCollateralSupplyTest();
    }

    function test_supply_05()
        public
        givenFirstSupply
        givenDebtCeilingGtZero
        givenUserDoesHaveIsolatedCollateralRole
        givenLtvIsNotZero
        whenUserIsUsingOtherCollateral
        whenUserIsUsingOneOtherCollateral
        givenOneOtherCollateralHasZeroDebtCeiling
    {
        _noAutomaticCollateralSupplyTest();
    }

    function test_supply_06()
        public
        givenFirstSupply
        givenDebtCeilingGtZero
        givenUserDoesHaveIsolatedCollateralRole
        givenLtvIsNotZero
        whenUserIsUsingOtherCollateral
        whenUserIsUsingMultipleOtherCollaterals
    {
        _noAutomaticCollateralSupplyTest();
    }

    function test_supply_07()
        public
        givenFirstSupply
        givenZeroDebtCeiling
        givenLtvIsZero
    {
        _noAutomaticCollateralSupplyTest();
    }

    function test_supply_08()
        public
        givenFirstSupply
        givenZeroDebtCeiling
        givenLtvIsNotZero
        whenUserIsNotUsingOtherCollateral
    {
        _automaticCollateralSupplyTest();
    }

    function test_supply_09()
        public
        givenFirstSupply
        givenZeroDebtCeiling
        givenLtvIsNotZero
        whenUserIsUsingOtherCollateral
        whenUserIsUsingOneOtherCollateral
        givenOneOtherCollateralHasDebtCeilingGtZero
    {
        _noAutomaticCollateralSupplyTest();
    }

    function test_supply_10()
        public
        givenFirstSupply
        givenZeroDebtCeiling
        givenLtvIsNotZero
        whenUserIsUsingOtherCollateral
        whenUserIsUsingOneOtherCollateral
        givenOneOtherCollateralHasZeroDebtCeiling
    {
        _automaticCollateralSupplyTest();
    }

    function test_supply_11()
        public
        givenFirstSupply
        givenZeroDebtCeiling
        givenLtvIsNotZero
        whenUserIsUsingOtherCollateral
        whenUserIsUsingMultipleOtherCollaterals
    {
        _automaticCollateralSupplyTest();
    }

    function test_supply_12()
        public
        givenNotFirstSupply
        givenNoTimeHasPassedAfterSupply
        givenNoActiveBorrow
    {
        _assertPoolReserveStateSupply({
            liquidityIndex:            1e27,
            currentLiquidityRate:      0,
            variableBorrowIndex:       1e27,
            currentVariableBorrowRate: 0.05e27,
            currentStableBorrowRate:   0.07e27,
            lastUpdateTimestamp:       1,
            accruedToTreasury:         0,
            unbacked:                  0
        });

        _assertATokenStateSupply({
            userBalance: 0,
            totalSupply: 500 ether
        });

        _assertAssetStateSupply({
            allowance:     1000 ether,
            userBalance:   1000 ether,
            aTokenBalance: 500 ether
        });

        assertEq(block.timestamp, 1);

        assertEq(
            pool.getUserConfiguration(supplier).isUsingAsCollateral(reserveId),
            false,
            "isUsingAsCollateral"
        );

        vm.prank(supplier);
        pool.supply(address(collateralAsset), 1000 ether, supplier, 0);

        _assertPoolReserveStateSupply({
            liquidityIndex:            1e27,
            currentLiquidityRate:      0,
            variableBorrowIndex:       1e27,
            currentVariableBorrowRate: 0.05e27,
            currentStableBorrowRate:   0.07e27,
            lastUpdateTimestamp:       1,
            accruedToTreasury:         0,
            unbacked:                  0
        });

        _assertATokenStateSupply({
            userBalance: 1000 ether,
            totalSupply: 1500 ether
        });

        _assertAssetStateSupply({
            allowance:     0,
            userBalance:   0,
            aTokenBalance: 1500 ether
        });

        assertEq(
            pool.getUserConfiguration(supplier).isUsingAsCollateral(reserveId),
            false,
            "isUsingAsCollateral"
        );
    }

    function test_supply_13()
        public
        givenNotFirstSupply
        givenNoTimeHasPassedAfterSupply
        givenActiveBorrow
        givenNoTimeHasPassedAfterBorrow
    {
        _assertPoolReserveStateSupply({
            liquidityIndex:            1e27,
            currentLiquidityRate:      0,
            variableBorrowIndex:       1e27,
            currentVariableBorrowRate: 0.05e27,
            currentStableBorrowRate:   0.07e27,
            lastUpdateTimestamp:       1,
            accruedToTreasury:         0,
            unbacked:                  0
        });

        // _assertATokenStateSupply({
        //     userBalance: 0,
        //     totalSupply: 500 ether
        // });

        // _assertAssetStateSupply({
        //     allowance:     1000 ether,
        //     userBalance:   1000 ether,
        //     aTokenBalance: 500 ether
        // });

        assertEq(block.timestamp, 1);

        // assertEq(
        //     pool.getUserConfiguration(supplier).isUsingAsCollateral(reserveId),
        //     false,
        //     "isUsingAsCollateral"
        // );

        // vm.prank(supplier);
        // pool.supply(address(collateralAsset), 1000 ether, supplier, 0);

        // _assertPoolReserveStateSupply({
        //     liquidityIndex:            1e27,
        //     currentLiquidityRate:      0,
        //     variableBorrowIndex:       1e27,
        //     currentVariableBorrowRate: 0.05e27,
        //     currentStableBorrowRate:   0.07e27,
        //     lastUpdateTimestamp:       1,
        //     accruedToTreasury:         0,
        //     unbacked:                  0
        // });

        // _assertATokenStateSupply({
        //     userBalance: 1000 ether,
        //     totalSupply: 1500 ether
        // });

        // _assertAssetStateSupply({
        //     allowance:     0,
        //     userBalance:   0,
        //     aTokenBalance: 1500 ether
        // });

        // assertEq(
        //     pool.getUserConfiguration(supplier).isUsingAsCollateral(reserveId),
        //     false,
        //     "isUsingAsCollateral"
        // );
    }

    // function test_supply_14()
    //     public
    //     givenNotFirstSupply
    //     givenSomeTimeHasPassedAfterSupply
    //     givenNoActiveBorrow
    // {
    //     _assertPoolReserveStateSupply({
    //         liquidityIndex:            1e27,
    //         currentLiquidityRate:      0,
    //         variableBorrowIndex:       1e27,
    //         currentVariableBorrowRate: 0.05e27,
    //         currentStableBorrowRate:   0.07e27,
    //         lastUpdateTimestamp:       1,
    //         accruedToTreasury:         0,
    //         unbacked:                  0
    //     });

    //     _assertATokenStateSupply({
    //         userBalance: 0,
    //         totalSupply: 500 ether
    //     });

    //     _assertAssetStateSupply({
    //         allowance:     1000 ether,
    //         userBalance:   1000 ether,
    //         aTokenBalance: 500 ether
    //     });

    //     assertEq(block.timestamp, 1000);

    //     assertEq(
    //         pool.getUserConfiguration(supplier).isUsingAsCollateral(reserveId),
    //         false,
    //         "isUsingAsCollateral"
    //     );

    //     vm.prank(supplier);
    //     pool.supply(address(collateralAsset), 1000 ether, supplier, 0);

    //     _assertPoolReserveStateSupply({
    //         liquidityIndex:            1e27,
    //         currentLiquidityRate:      0,
    //         variableBorrowIndex:       1e27,
    //         currentVariableBorrowRate: 0.05e27,
    //         currentStableBorrowRate:   0.07e27,
    //         lastUpdateTimestamp:       1000,  // lastUpdated has been changed
    //         accruedToTreasury:         0,
    //         unbacked:                  0
    //     });

    //     _assertATokenStateSupply({
    //         userBalance: 1000 ether,
    //         totalSupply: 1500 ether
    //     });

    //     _assertAssetStateSupply({
    //         allowance:     0,
    //         userBalance:   0,
    //         aTokenBalance: 1500 ether
    //     });

    //     assertEq(
    //         pool.getUserConfiguration(supplier).isUsingAsCollateral(reserveId),
    //         false,
    //         "isUsingAsCollateral"
    //     );
    // }

    // function test_supply_15()
    //     public
    //     givenNotFirstSupply
    //     givenSomeTimeHasPassedAfterSupply
    //     givenActiveBorrow
    // {
    //     _assertPoolReserveStateSupply({
    //         liquidityIndex:            1e27,
    //         currentLiquidityRate:      0,
    //         variableBorrowIndex:       1e27,
    //         currentVariableBorrowRate: 0.05e27,
    //         currentStableBorrowRate:   0.07e27,
    //         lastUpdateTimestamp:       1,
    //         accruedToTreasury:         0,
    //         unbacked:                  0
    //     });

    //     _assertATokenStateSupply({
    //         userBalance: 0,
    //         totalSupply: 500 ether
    //     });

    //     _assertAssetStateSupply({
    //         allowance:     1000 ether,
    //         userBalance:   1000 ether,
    //         aTokenBalance: 500 ether
    //     });

    //     assertEq(block.timestamp, 1000);

    //     assertEq(
    //         pool.getUserConfiguration(supplier).isUsingAsCollateral(reserveId),
    //         false,
    //         "isUsingAsCollateral"
    //     );

    //     vm.prank(supplier);
    //     pool.supply(address(collateralAsset), 1000 ether, supplier, 0);

    //     _assertPoolReserveStateSupply({
    //         liquidityIndex:            1e27,
    //         currentLiquidityRate:      0,
    //         variableBorrowIndex:       1e27,
    //         currentVariableBorrowRate: 0.05e27,
    //         currentStableBorrowRate:   0.07e27,
    //         lastUpdateTimestamp:       1000,  // lastUpdated has been changed
    //         accruedToTreasury:         0,
    //         unbacked:                  0
    //     });

    //     _assertATokenStateSupply({
    //         userBalance: 1000 ether,
    //         totalSupply: 1500 ether
    //     });

    //     _assertAssetStateSupply({
    //         allowance:     0,
    //         userBalance:   0,
    //         aTokenBalance: 1500 ether
    //     });

    //     assertEq(
    //         pool.getUserConfiguration(supplier).isUsingAsCollateral(reserveId),
    //         false,
    //         "isUsingAsCollateral"
    //     );
    // }

    /**********************************************************************************************/
    /*** Test running functions                                                                 ***/
    /**********************************************************************************************/

    function _noAutomaticCollateralSupplyTest() internal {
        _assertPoolReserveStateSupply({
            liquidityIndex:            1e27,
            currentLiquidityRate:      0,
            variableBorrowIndex:       1e27,
            currentVariableBorrowRate: 0,
            currentStableBorrowRate:   0,
            lastUpdateTimestamp:       0,
            accruedToTreasury:         0,
            unbacked:                  0
        });

        _assertATokenStateSupply({
            userBalance: 0,
            totalSupply: 0
        });

        _assertAssetStateSupply({
            allowance:     1000 ether,
            userBalance:   1000 ether,
            aTokenBalance: 0
        });

        assertEq(block.timestamp, 1);

        assertEq(
            pool.getUserConfiguration(supplier).isUsingAsCollateral(reserveId),
            false,
            "isUsingAsCollateral"
        );

        vm.prank(supplier);
        pool.supply(address(collateralAsset), 1000 ether, supplier, 0);

        _assertPoolReserveStateSupply({
            liquidityIndex:            1e27,
            currentLiquidityRate:      0,
            variableBorrowIndex:       1e27,
            currentVariableBorrowRate: 0.05e27,
            currentStableBorrowRate:   0.07e27,
            lastUpdateTimestamp:       1,
            accruedToTreasury:         0,
            unbacked:                  0
        });

        _assertATokenStateSupply({
            userBalance: 1000 ether,
            totalSupply: 1000 ether
        });

        _assertAssetStateSupply({
            allowance:     0,
            userBalance:   0,
            aTokenBalance: 1000 ether
        });

        assertEq(
            pool.getUserConfiguration(supplier).isUsingAsCollateral(reserveId),
            false,
            "isUsingAsCollateral"
        );
    }

    function _automaticCollateralSupplyTest() internal {
        _assertPoolReserveStateSupply({
            liquidityIndex:            1e27,
            currentLiquidityRate:      0,
            variableBorrowIndex:       1e27,
            currentVariableBorrowRate: 0,
            currentStableBorrowRate:   0,
            lastUpdateTimestamp:       0,
            accruedToTreasury:         0,
            unbacked:                  0
        });

        _assertATokenStateSupply({
            userBalance: 0,
            totalSupply: 0
        });

        _assertAssetStateSupply({
            allowance:     1000 ether,
            userBalance:   1000 ether,
            aTokenBalance: 0
        });

        assertEq(block.timestamp, 1);

        assertEq(
            pool.getUserConfiguration(supplier).isUsingAsCollateral(reserveId),
            false,
            "isUsingAsCollateral"
        );

        vm.prank(supplier);
        pool.supply(address(collateralAsset), 1000 ether, supplier, 0);

        _assertPoolReserveStateSupply({
            liquidityIndex:            1e27,
            currentLiquidityRate:      0,
            variableBorrowIndex:       1e27,
            currentVariableBorrowRate: 0.05e27,
            currentStableBorrowRate:   0.07e27,
            lastUpdateTimestamp:       1,
            accruedToTreasury:         0,
            unbacked:                  0
        });

        _assertATokenStateSupply({
            userBalance: 1000 ether,
            totalSupply: 1000 ether
        });

        _assertAssetStateSupply({
            allowance:     0,
            userBalance:   0,
            aTokenBalance: 1000 ether
        });

        assertEq(
            pool.getUserConfiguration(supplier).isUsingAsCollateral(reserveId),
            true,
            "isUsingAsCollateral"
        );
    }

    /**********************************************************************************************/
    /*** Assertion helper functions                                                             ***/
    /**********************************************************************************************/

    function _assertPoolReserveStateSupply(
        uint256 liquidityIndex,
        uint256 currentLiquidityRate,
        uint256 variableBorrowIndex,
        uint256 currentVariableBorrowRate,
        uint256 currentStableBorrowRate,
        uint256 lastUpdateTimestamp,
        uint256 accruedToTreasury,
        uint256 unbacked
    ) internal {
        assertEq(pool.getReserveData(address(collateralAsset)).liquidityIndex,            liquidityIndex,            "liquidityIndex");
        assertEq(pool.getReserveData(address(collateralAsset)).currentLiquidityRate,      currentLiquidityRate,      "currentLiquidityRate");
        assertEq(pool.getReserveData(address(collateralAsset)).variableBorrowIndex,       variableBorrowIndex,       "variableBorrowIndex");
        assertEq(pool.getReserveData(address(collateralAsset)).currentVariableBorrowRate, currentVariableBorrowRate, "currentVariableBorrowRate");
        assertEq(pool.getReserveData(address(collateralAsset)).currentStableBorrowRate,   currentStableBorrowRate,   "currentStableBorrowRate");
        assertEq(pool.getReserveData(address(collateralAsset)).lastUpdateTimestamp,       lastUpdateTimestamp,       "lastUpdateTimestamp");
        assertEq(pool.getReserveData(address(collateralAsset)).accruedToTreasury,         accruedToTreasury,         "accruedToTreasury");
        assertEq(pool.getReserveData(address(collateralAsset)).unbacked,                  unbacked,                  "unbacked");

        // NOTE: Intentionally left out the following as they do not change on supply
        // - ReserveConfigurationMap configuration;
        // - uint16 id;
        // - address aTokenAddress;
        // - address stableDebtTokenAddress;
        // - address variableDebtTokenAddress;
        // - address interestRateStrategyAddress;
        // - uint128 isolationModeTotalDebt;
    }

    function _assertAssetStateSupply(uint256 allowance, uint256 userBalance, uint256 aTokenBalance) internal {
        assertEq(collateralAsset.allowance(supplier, address(pool)), allowance,     "allowance");
        assertEq(collateralAsset.balanceOf(supplier),                userBalance,   "userBalance");
        assertEq(collateralAsset.balanceOf(address(aToken)),         aTokenBalance, "aTokenBalance");
    }

    function _assertATokenStateSupply(uint256 userBalance, uint256 totalSupply) internal {
        assertEq(aToken.balanceOf(supplier), userBalance, "userBalance");
        assertEq(aToken.totalSupply(),       totalSupply, "totalSupply");
    }

}

