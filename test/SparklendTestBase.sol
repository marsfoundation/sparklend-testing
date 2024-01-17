// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { VmSafe } from "forge-std/Vm.sol";

import { AaveOracle }                               from "aave-v3-core/contracts/misc/AaveOracle.sol";
import { AaveProtocolDataProvider as DataProvider } from "aave-v3-core/contracts/misc/AaveProtocolDataProvider.sol";

import { ACLManager }                    from "aave-v3-core/contracts/protocol/configuration/ACLManager.sol";
import { PoolAddressesProvider }         from "aave-v3-core/contracts/protocol/configuration/PoolAddressesProvider.sol";
import { PoolAddressesProviderRegistry } from "aave-v3-core/contracts/protocol/configuration/PoolAddressesProviderRegistry.sol";

import { Pool }                               from "aave-v3-core/contracts/protocol/pool/Pool.sol";
import { PoolConfigurator }                   from "aave-v3-core/contracts/protocol/pool/PoolConfigurator.sol";

import { ConfiguratorInputTypes } from "aave-v3-core/contracts/protocol/libraries/types/ConfiguratorInputTypes.sol";

import { AToken }            from "aave-v3-core/contracts/protocol/tokenization/AToken.sol";
import { StableDebtToken }   from "aave-v3-core/contracts/protocol/tokenization/StableDebtToken.sol";
import { VariableDebtToken } from "aave-v3-core/contracts/protocol/tokenization/VariableDebtToken.sol";

import { IReserveInterestRateStrategy } from "aave-v3-core/contracts/interfaces/IReserveInterestRateStrategy.sol";

import { VariableBorrowInterestRateStrategy } from "sparklend-advanced/VariableBorrowInterestRateStrategy.sol";

import { IERC20 }    from "erc20-helpers/interfaces/IERC20.sol";
import { MockERC20 } from "erc20-helpers/MockERC20.sol";

import { MockOracle } from "test/mocks/MockOracle.sol";

// TODO: Is the deploy a pool admin on mainnet?
// TODO: Figure out where token implementations need to be configured.
// TODO: Remove unnecessary imports.

contract SparkLendTestBase is Test {

    address admin = makeAddr("admin");

    AaveOracle            aaveOracle;
    ACLManager            aclManager;
    DataProvider          protocolDataProvider;
    Pool                  pool;
    PoolAddressesProvider poolAddressesProvider;
    PoolConfigurator      poolConfigurator;

    AToken            aTokenImpl;
    StableDebtToken   stableDebtTokenImpl;
    VariableDebtToken variableDebtTokenImpl;

    MockERC20 borrowAsset;
    MockERC20 collateralAsset;

    function setUp() public virtual {
        address deployer = address(this);

        poolAddressesProvider = new PoolAddressesProvider("0", deployer);

        PoolConfigurator poolConfiguratorImpl = new PoolConfigurator();

        PoolAddressesProviderRegistry registry = new PoolAddressesProviderRegistry(deployer);

        poolAddressesProvider.setACLAdmin(deployer);

        aclManager           = new ACLManager(poolAddressesProvider);
        protocolDataProvider = new DataProvider(poolAddressesProvider);

        Pool poolImpl = new Pool(poolAddressesProvider);

        poolAddressesProvider.setPoolImpl(address(poolImpl));
        poolAddressesProvider.setPoolConfiguratorImpl(address(poolConfiguratorImpl));

        pool             = Pool(poolAddressesProvider.getPool());
        poolConfigurator = PoolConfigurator(poolAddressesProvider.getPoolConfigurator());

        aTokenImpl            = new AToken(pool);
        stableDebtTokenImpl   = new StableDebtToken(pool);
        variableDebtTokenImpl = new VariableDebtToken(pool);

        address[] memory assets;
        address[] memory oracles;
        aaveOracle = new AaveOracle({
            provider:         poolAddressesProvider,
            assets:           assets,
            sources:          oracles,
            fallbackOracle:   address(0),
            baseCurrency:     address(0),  // USD
            baseCurrencyUnit: 1e8
        });

        poolAddressesProvider.setACLAdmin(deployer);
        poolAddressesProvider.setACLManager(address(aclManager));
        poolAddressesProvider.setPoolDataProvider(address(protocolDataProvider));
        poolAddressesProvider.setPriceOracle(address(aaveOracle));

        registry.registerAddressesProvider(address(poolAddressesProvider), 1);

        aclManager.addEmergencyAdmin(admin);
        aclManager.addPoolAdmin(admin);
        aclManager.removePoolAdmin(deployer);
        aclManager.grantRole(aclManager.DEFAULT_ADMIN_ROLE(), admin);
        aclManager.revokeRole(aclManager.DEFAULT_ADMIN_ROLE(), deployer);

        poolAddressesProvider.setACLAdmin(admin);
        poolAddressesProvider.transferOwnership(admin);

        registry.transferOwnership(admin);

        IReserveInterestRateStrategy strategy
            = IReserveInterestRateStrategy(new VariableBorrowInterestRateStrategy({
                provider:               poolAddressesProvider,
                optimalUsageRatio:      0.90e27,
                baseVariableBorrowRate: 0.05e27,
                variableRateSlope1:     0.02e27,
                variableRateSlope2:     0.3e27
            }));

        collateralAsset = new MockERC20("Collateral Asset", "COLL", 18);
        borrowAsset     = new MockERC20("Borrow Asset",     "BRRW", 18);

        _initReserve(IERC20(address(collateralAsset)), strategy);  // TODO: Use different strategy
        _initReserve(IERC20(address(borrowAsset)),     strategy);

        _setUpMockOracle(address(collateralAsset), int256(1e8));
        _setUpMockOracle(address(borrowAsset),     int256(1e8));
    }

    /**********************************************************************************************/
    /*** Admin helper functions                                                                 ***/
    /**********************************************************************************************/

    function _initReserve(IERC20 token, IReserveInterestRateStrategy strategy) internal {
        string memory symbol = token.symbol();

        ConfiguratorInputTypes.InitReserveInput[] memory reserveInputs
            = new ConfiguratorInputTypes.InitReserveInput[](1);

        reserveInputs[0] = ConfiguratorInputTypes.InitReserveInput({
            aTokenImpl:                  address(aTokenImpl),
            stableDebtTokenImpl:         address(stableDebtTokenImpl),
            variableDebtTokenImpl:       address(variableDebtTokenImpl),
            underlyingAssetDecimals:     token.decimals(),
            interestRateStrategyAddress: address(strategy),
            underlyingAsset:             address(token),
            treasury:                    address(token),  // TODO: Change to treasury
            incentivesController:        address(0),
            aTokenName:                  string(string.concat("Spark ",               symbol)),
            aTokenSymbol:                string(string.concat("sp",                   symbol)),
            variableDebtTokenName:       string(string.concat("Spark Variable Debt ", symbol)),
            variableDebtTokenSymbol:     string(string.concat("variableDebt",         symbol)),
            stableDebtTokenName:         string(string.concat("Spark Stable Debt ",   symbol)),
            stableDebtTokenSymbol:       string(string.concat("stableDebt",           symbol)),
            params:                      ""
        });

        vm.prank(admin);
        poolConfigurator.initReserves(reserveInputs);
    }

    function _setUpMockOracle(address asset, int256 price) internal {
        MockOracle oracle = new MockOracle();

        oracle.__setPrice(int256(price));

        address[] memory assets  = new address[](1);
        address[] memory sources = new address[](1);
        assets[0]  = asset;
        sources[0] = address(oracle);

        vm.prank(admin);
        aaveOracle.setAssetSources(assets, sources);
    }

    function _initCollateral(
        address asset,
        uint256 ltv,
        uint256 liquidationThreshold,
        uint256 liquidationBonus
    )
        internal
    {
        // Set LTV to 1%
        vm.prank(admin);
        poolConfigurator.configureReserveAsCollateral(
            asset,
            ltv,
            liquidationThreshold,
            liquidationBonus
        );
    }

    // TODO: More parameters
    function _setUpNewCollateral() internal returns (address newCollateralAsset) {
        IReserveInterestRateStrategy strategy
            = IReserveInterestRateStrategy(new VariableBorrowInterestRateStrategy({
                provider:                      poolAddressesProvider,
                optimalUsageRatio:             0.90e27,
                baseVariableBorrowRate:        0.05e27,
                variableRateSlope1:            0.02e27,
                variableRateSlope2:            0.3e27
            }));

        newCollateralAsset = address(new MockERC20("Collateral Asset", "COLL", 18));

        _initReserve(IERC20(newCollateralAsset), strategy);
        _setUpMockOracle(newCollateralAsset, int256(1e8));

        // Set LTV to 1%
        vm.prank(admin);
        poolConfigurator.configureReserveAsCollateral(newCollateralAsset, 100, 100, 100_01);
    }

    /**********************************************************************************************/
    /*** User helper functions                                                                  ***/
    /**********************************************************************************************/

    function _useAsCollateral(address user, address newCollateralAsset) internal {
        vm.prank(user);
        pool.setUserUseReserveAsCollateral(newCollateralAsset, true);
    }

    function _borrow(address user, address borrowAsset_, uint256 amount) internal {
        vm.startPrank(user);
        pool.borrow(borrowAsset_, amount, 2, 0, user);
        vm.stopPrank();
    }

    function _supply(address user, address collateralAsset_, uint256 amount) internal {
        vm.startPrank(user);
        MockERC20(collateralAsset_).mint(user, amount);
        MockERC20(collateralAsset_).approve(address(pool), amount);
        pool.supply(collateralAsset_, amount, user, 0);
        vm.stopPrank();
    }

    function _supplyAndUseAsCollateral(address user, address collateralAsset_, uint256 amount)
        internal
    {
        _supply(user, collateralAsset_, amount);
        _useAsCollateral(user, collateralAsset_);
    }

    function _setCollateralDebtCeiling(address collateralAsset_, uint256 ceiling) internal {
        vm.prank(admin);
        poolConfigurator.setDebtCeiling(collateralAsset_, ceiling);
    }

    /**********************************************************************************************/
    /*** View helper functions                                                                  ***/
    /**********************************************************************************************/

    function _getAToken(address reserve) internal view returns (address aToken) {
        return pool.getReserveData(reserve).aTokenAddress;
    }

    /**********************************************************************************************/
    /*** State diff functions and modifiers                                                     ***/
    /**********************************************************************************************/

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

    function _logAddressOrUint(string memory key, bytes32 _bytes) internal view {
        if (isAddress(_bytes)) {
            console.log(key, vm.toString(bytes32ToAddress(_bytes)));
        } else {
            console.log(key, vm.toString(uint256(_bytes)));
        }
    }

    function isAddress(bytes32 _bytes) public pure returns (bool isAddress_) {
        if (_bytes == 0) return false;

        for (uint256 i = 20; i < 32; i++) {
            if (_bytes[i] != 0) return false;
        }
        isAddress_ = true;
    }

    function bytes32ToAddress(bytes32 _bytes) public pure returns (address) {
        require(isAddress(_bytes), "bytes32ToAddress/invalid-address");
        return address(uint160(uint256(_bytes)));
    }

}
