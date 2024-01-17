// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { VmSafe } from "forge-std/Vm.sol";

import { UserConfiguration } from "aave-v3-core/protocol/libraries/configuration/UserConfiguration.sol";
import { Errors }            from "aave-v3-core/protocol/libraries/helpers/Errors.sol";
import { DataTypes }         from "aave-v3-core/protocol/libraries/types/DataTypes.sol";
import { IAToken }           from "aave-v3-core/protocol/tokenization/AToken.sol";

import {
    DefaultReserveInterestRateStrategy,
    IERC20,
    IReserveInterestRateStrategy,
    MockERC20,
    SparkLendTestBase
} from "./SparkLendTestBase.sol";

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

    modifier givenNoTimeHasPassed { _; }

    modifier givenSomeTimeHasPassed() {
        vm.warp(1000 seconds);
        _;
    }

    modifier logStateDiff() {
        vm.startStateDiffRecording();

        _;

        VmSafe.AccountAccess[] memory records = vm.stopAndReturnStateDiff();

        console.log("--- STATE DIFF ---");

        for (uint256 i = 0; i < records.length; i++) {
            for (uint256 j; j < records[i].storageAccesses.length; j++) {
                if (!records[i].storageAccesses[j].isWrite) continue;

                if (
                    records[i].storageAccesses[j].newValue ==
                    records[i].storageAccesses[j].previousValue
                ) continue;

                console.log("");
                console2.log("account:  %s", vm.getLabel(records[i].account));
                console2.log("accessor: %s", vm.getLabel(records[i].accessor));
                console2.log("slot:     %s", vm.toString(records[i].storageAccesses[j].slot));

                _logAddressOrUint("oldValue:", records[i].storageAccesses[j].previousValue);
                _logAddressOrUint("newValue:", records[i].storageAccesses[j].newValue);
            }
        }
    }

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

    function test_supply_01()
        public
        givenFirstSupply
        givenDebtCeilingGtZero
        givenUserHasNoIsolatedCollateralRole
        logStateDiff
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
        givenNoTimeHasPassed
    {
        _assertATokenStateSupply({
            userBalance: 0,
            totalSupply: 500 ether
        });

        _assertAssetStateSupply({
            allowance:     1000 ether,
            userBalance:   1000 ether,
            aTokenBalance: 500 ether
        });

        vm.prank(supplier);
        pool.supply(address(collateralAsset), 1000 ether, supplier, 0);

        _assertATokenStateSupply({
            userBalance: 1000 ether,
            totalSupply: 1500 ether
        });

        _assertAssetStateSupply({
            allowance:     0,
            userBalance:   0,
            aTokenBalance: 1500 ether
        });
    }

    function _logSlot(address target, bytes32 slot) internal view {
        console2.log(
            "slot: %s, value: %s",
            vm.toString(slot), vm.toString(uint256(vm.load(target, slot)))
        );
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

    function _logAddressOrUint(string memory key, bytes32 _bytes) internal view {
        if (isAddress(_bytes)) {
            console.log(key, vm.toString(bytes32ToAddress(_bytes)));
        } else {
            console.log(key, vm.toString(uint256(_bytes)));
        }
    }

    function isAddress(bytes32 _bytes) public view returns (bool isAddress_) {
        if (_bytes == 0) return false;

        for (uint256 i = 20; i < 32; i++) {
            if (_bytes[i] != 0) return false;
        }
        isAddress_ = true;
    }

    function bytes32ToAddress(bytes32 _bytes) public view returns (address) {
        require(isAddress(_bytes), "bytes32ToAddress/invalid-address");
        return address(uint160(uint256(_bytes)));
    }

    function _useAsCollateral(address user, address newCollateralAsset) internal {
        vm.prank(user);
        pool.setUserUseReserveAsCollateral(newCollateralAsset, true);
    }

    function _supply(address user, address newCollateralAsset, uint256 amount) internal {
        vm.startPrank(user);
        MockERC20(newCollateralAsset).mint(user, amount);
        MockERC20(newCollateralAsset).approve(address(pool), amount);
        pool.supply(newCollateralAsset, amount, user, 0);
        vm.stopPrank();
    }

    function _supplyAndUseAsCollateral(address user, address newCollateralAsset, uint256 amount) internal {
        _supply(user, newCollateralAsset, amount);
        _useAsCollateral(user, newCollateralAsset);
    }

    function _setCollateralDebtCeiling(address newCollateralAsset, uint256 ceiling) internal {
        vm.prank(admin);
        poolConfigurator.setDebtCeiling(newCollateralAsset, ceiling);
    }

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

    function _assertAssetStateSupply(
        uint256 allowance,
        uint256 userBalance,
        uint256 aTokenBalance
    )
        internal
    {
        assertEq(collateralAsset.allowance(supplier, address(pool)), allowance,     "allowance");
        assertEq(collateralAsset.balanceOf(supplier),                userBalance,   "userBalance");
        assertEq(collateralAsset.balanceOf(address(aToken)),         aTokenBalance, "aTokenBalance");
    }

    function _assertATokenStateSupply(
        uint256 userBalance,
        uint256 totalSupply
    )
        internal
    {
        assertEq(aToken.balanceOf(supplier), userBalance, "userBalance");
        assertEq(aToken.totalSupply(),       totalSupply, "totalSupply");
    }

}

