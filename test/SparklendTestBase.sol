// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.13;

// TODO: Set up remappings

import "forge-std/Test.sol";

import { InitializableAdminUpgradeabilityProxy } from "aave-v3-core/contracts/dependencies/openzeppelin/upgradeability/InitializableAdminUpgradeabilityProxy.sol";

import { AaveOracle }                               from "aave-v3-core/contracts/misc/AaveOracle.sol";
import { AaveProtocolDataProvider as DataProvider } from "aave-v3-core/contracts/misc/AaveProtocolDataProvider.sol";

import { Pool }             from "aave-v3-core/contracts/protocol/pool/Pool.sol";
import { PoolConfigurator } from "aave-v3-core/contracts/protocol/pool/PoolConfigurator.sol";

import { ACLManager }                    from "aave-v3-core/contracts/protocol/configuration/ACLManager.sol";
import { PoolAddressesProvider }         from "aave-v3-core/contracts/protocol/configuration/PoolAddressesProvider.sol";
import { PoolAddressesProviderRegistry } from "aave-v3-core/contracts/protocol/configuration/PoolAddressesProviderRegistry.sol";

import { AToken }            from "aave-v3-core/contracts/protocol/tokenization/AToken.sol";
import { StableDebtToken }   from "aave-v3-core/contracts/protocol/tokenization/StableDebtToken.sol";
import { VariableDebtToken } from "aave-v3-core/contracts/protocol/tokenization/VariableDebtToken.sol";

import { IAaveIncentivesController } from "aave-v3-core/contracts/interfaces/IAaveIncentivesController.sol";
import { IPool }                     from "aave-v3-core/contracts/interfaces/IPool.sol";

// TODO: Is the deploy a pool admin on mainnet?
// TODO: Figure out where token implementations need to be configured.
// TODO: Remove unnecessary imports.

contract SparklendTestBase is Test {

    address admin = makeAddr("admin");

    Pool             pool;
    PoolConfigurator poolConfigurator;

    function setUp() public virtual {
        address deployer = address(this);

        PoolAddressesProvider poolAddressesProvider = new PoolAddressesProvider("0", deployer);
        PoolConfigurator      poolConfiguratorImpl  = new PoolConfigurator();

        PoolAddressesProviderRegistry registry = new PoolAddressesProviderRegistry(deployer);

        poolAddressesProvider.setACLAdmin(deployer);

        ACLManager   aclManager           = new ACLManager(poolAddressesProvider);
        Pool         poolImpl             = new Pool(poolAddressesProvider);
        DataProvider protocolDataProvider = new DataProvider(poolAddressesProvider);

        poolAddressesProvider.setPoolImpl(address(poolImpl));
        poolAddressesProvider.setPoolConfiguratorImpl(address(poolConfiguratorImpl));

        pool             = Pool(poolAddressesProvider.getPool());
        poolConfigurator = PoolConfigurator(poolAddressesProvider.getPoolConfigurator());

        AToken            aTokenImpl            = new AToken(pool);
        StableDebtToken   stableDebtTokenImpl   = new StableDebtToken(pool);
        VariableDebtToken variableDebtTokenImpl = new VariableDebtToken(pool);

        address[] memory assets;
        address[] memory oracles;
        AaveOracle aaveOracle = new AaveOracle({
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
    }

    function test_example() public {

    }
}
