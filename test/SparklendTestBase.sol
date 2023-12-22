// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { AaveOracle }                               from "aave-v3-core/misc/AaveOracle.sol";
import { AaveProtocolDataProvider as DataProvider } from "aave-v3-core/misc/AaveProtocolDataProvider.sol";

import { ACLManager }                    from "aave-v3-core/protocol/configuration/ACLManager.sol";
import { PoolAddressesProvider }         from "aave-v3-core/protocol/configuration/PoolAddressesProvider.sol";
import { PoolAddressesProviderRegistry } from "aave-v3-core/protocol/configuration/PoolAddressesProviderRegistry.sol";

import { DefaultReserveInterestRateStrategy } from "aave-v3-core/protocol/pool/DefaultReserveInterestRateStrategy.sol";
import { Pool }                               from "aave-v3-core/protocol/pool/Pool.sol";
import { PoolConfigurator }                   from "aave-v3-core/protocol/pool/PoolConfigurator.sol";

import { ConfiguratorInputTypes } from "aave-v3-core/protocol/libraries/types/ConfiguratorInputTypes.sol";

import { AToken }            from "aave-v3-core/protocol/tokenization/AToken.sol";
import { StableDebtToken }   from "aave-v3-core/protocol/tokenization/StableDebtToken.sol";
import { VariableDebtToken } from "aave-v3-core/protocol/tokenization/VariableDebtToken.sol";

import { IReserveInterestRateStrategy } from "aave-v3-core/interfaces/IReserveInterestRateStrategy.sol";

import { IERC20 }    from "erc20-helpers/interfaces/IERC20.sol";
import { MockERC20 } from "erc20-helpers/MockERC20.sol";

import { MockOracle } from "./mocks/MockOracle.sol";

// TODO: Is the deploy a pool admin on mainnet?
// TODO: Figure out where token implementations need to be configured.
// TODO: Remove unnecessary imports.

contract SparklendTestBase is Test {

    address admin = makeAddr("admin");

    AaveOracle            aaveOracle;
    ACLManager            aclManager;
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

        aclManager = new ACLManager(poolAddressesProvider);

        Pool         poolImpl             = new Pool(poolAddressesProvider);
        DataProvider protocolDataProvider = new DataProvider(poolAddressesProvider);

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

        collateralAsset = new MockERC20("Collateral Asset", "COLL", 18);
        borrowAsset     = new MockERC20("Borrow Asset",     "BRRW", 18);

        _initReserve(IERC20(address(collateralAsset)), strategy);  // TODO: Use different strategy
        _initReserve(IERC20(address(borrowAsset)),     strategy);

        _setUpMockOracle(address(collateralAsset), int256(1e8));
        _setUpMockOracle(address(borrowAsset),     int256(1e8));
    }

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

}
