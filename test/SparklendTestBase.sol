// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.13;

// TODO: Set up remappings

import "forge-std/Test.sol";

import { InitializableAdminUpgradeabilityProxy } from 'aave-v3-core/contracts/dependencies/openzeppelin/upgradeability/InitializableAdminUpgradeabilityProxy.sol';

import { AaveOracle }                               from 'aave-v3-core/contracts/misc/AaveOracle.sol';
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

// import { Collector }           from "lib/aave-v3-periphery/contracts/treasury/Collector.sol";
// import { CollectorController } from "lib/aave-v3-periphery/contracts/treasury/CollectorController.sol";
// import { RewardsController }   from "lib/aave-v3-periphery/contracts/rewards/RewardsController.sol";
// import { EmissionManager }     from "lib/aave-v3-periphery/contracts/rewards/EmissionManager.sol";

// import { IEACAggregatorProxy }       from "lib/aave-v3-periphery/contracts/misc/interfaces/IEACAggregatorProxy.sol";
// import { UiIncentiveDataProviderV3 } from "lib/aave-v3-periphery/contracts/misc/UiIncentiveDataProviderV3.sol";
// import { UiPoolDataProviderV3 }      from "lib/aave-v3-periphery/contracts/misc/UiPoolDataProviderV3.sol";
// import { WalletBalanceProvider }     from "lib/aave-v3-periphery/contracts/misc/WalletBalanceProvider.sol";
// import { WrappedTokenGatewayV3 }     from "lib/aave-v3-periphery/contracts/misc/WrappedTokenGatewayV3.sol";

// TODO: Use git for submodules

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
            provider: poolAddressesProvider,
            assets: assets,
            sources: oracles,
            fallbackOracle: address(0),
            baseCurrency: address(0),  // USD
            baseCurrencyUnit: 1e8
        });

        aclManager.addPoolAdmin(deployer);  // TODO: Why is this needed?

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

    function test_example() public virtual {

    }
}

// contract DeploySpark is Script {

//     using stdJson for string;
//     using ScriptTools for string;

//     uint256 constant RAY = 10 ** 27;

//     string config;
//     string instanceId;

//     address admin;
//     address deployer;

//     PoolAddressesProviderRegistry registry;
//     PoolAddressesProvider poolAddressesProvider;
//     AaveProtocolDataProvider protocolDataProvider;
//     PoolConfigurator poolConfigurator;
//     PoolConfigurator poolConfiguratorImpl;
//     Pool pool;
//     Pool poolImpl;
//     ACLManager aclManager;
//     AaveOracle aaveOracle;

//     AToken aTokenImpl;
//     StableDebtToken stableDebtTokenImpl;
//     VariableDebtToken variableDebtTokenImpl;

//     Collector treasury;
//     address treasuryImpl;
//     CollectorController treasuryController;
//     RewardsController incentives;
//     EmissionManager emissionManager;
//     Collector collectorImpl;

//     UiPoolDataProviderV3 uiPoolDataProvider;
//     UiIncentiveDataProviderV3 uiIncentiveDataProvider;
//     WrappedTokenGatewayV3 wethGateway;
//     WalletBalanceProvider walletBalanceProvider;

//     InitializableAdminUpgradeabilityProxy incentivesProxy;
//     RewardsController rewardsController;
//     IEACAggregatorProxy proxy;

//     function run() external {
//         //vm.createSelectFork(vm.envString("ETH_RPC_URL"));     // Multi-chain not supported in Foundry yet (use CLI arg for now)
//         instanceId = vm.envOr("INSTANCE_ID", string("primary"));
//         vm.setEnv("FOUNDRY_ROOT_CHAINID", vm.toString(block.chainid));

//         config = ScriptTools.loadConfig(instanceId);

//         admin    = config.readAddress(".admin");
//         deployer = msg.sender;

//         vm.startBroadcast();

//         // 1. Deploy and configure registry and addresses provider

//         registry              = new PoolAddressesProviderRegistry(deployer);
//         poolAddressesProvider = new PoolAddressesProvider(config.readString(".marketId"), deployer);

//         poolAddressesProvider.setACLAdmin(deployer);

//         // 2. Deploy data provider and pool configurator, initialize pool configurator

//         protocolDataProvider = new AaveProtocolDataProvider(poolAddressesProvider);
//         poolConfiguratorImpl = new PoolConfigurator();

//         poolConfiguratorImpl.initialize(poolAddressesProvider);

//         // 3. Deploy pool implementation and initialize

//         poolImpl = new Pool(poolAddressesProvider);
//         poolImpl.initialize(poolAddressesProvider);

//         // 4. Deploy and configure ACL manager

//         aclManager = new ACLManager(poolAddressesProvider);
//         aclManager.addPoolAdmin(deployer);

//         // 5. Additional configuration for registry and pool address provider

//         registry.registerAddressesProvider(address(poolAddressesProvider), 1);

//         poolAddressesProvider.setPoolDataProvider(address(protocolDataProvider));
//         poolAddressesProvider.setPoolImpl(address(poolImpl));

//         // 6. Get pool instance

//         pool = Pool(poolAddressesProvider.getPool());

//         // 7. Set the Pool Configurator implementation and ACL manager and get the pool configurator instance

//         poolAddressesProvider.setPoolConfiguratorImpl(address(poolConfiguratorImpl));
//         poolConfigurator = PoolConfigurator(poolAddressesProvider.getPoolConfigurator());
//         poolAddressesProvider.setACLManager(address(aclManager));

//         // 8. Deploy and initialize aToken instance

//         aTokenImpl = new AToken(pool);
//         aTokenImpl.initialize(pool, address(0), address(0), IAaveIncentivesController(address(0)), 0, "SPTOKEN_IMPL", "SPTOKEN_IMPL", "");

//         // 9. Deploy and initialize stableDebtToken instance

//         stableDebtTokenImpl = new StableDebtToken(pool);
//         stableDebtTokenImpl.initialize(pool, address(0), IAaveIncentivesController(address(0)), 0, "STABLE_DEBT_TOKEN_IMPL", "STABLE_DEBT_TOKEN_IMPL", "");

//         // 9. Deploy and initialize variableDebtToken instance

//         variableDebtTokenImpl = new VariableDebtToken(pool);
//         variableDebtTokenImpl.initialize(pool, address(0), IAaveIncentivesController(address(0)), 0, "VARIABLE_DEBT_TOKEN_IMPL", "VARIABLE_DEBT_TOKEN_IMPL", "");

//         // 10. Deploy Collector, CollectorController and treasury contracts.

//         treasuryController = new CollectorController(admin);
//         collectorImpl      = new Collector();

//         collectorImpl.initialize(address(0));

//         (treasury, treasuryImpl) = createCollector(admin);

//         // 11. Deploy initialize and configure rewards contracts.

//         incentivesProxy   = new InitializableAdminUpgradeabilityProxy();
//         incentives        = RewardsController(address(incentivesProxy));
//         emissionManager   = new EmissionManager(deployer);
//         rewardsController = new RewardsController(address(emissionManager));

//         rewardsController.initialize(address(0));
//         incentivesProxy.initialize(
//             address(rewardsController),
//             admin,
//             abi.encodeWithSignature("initialize(address)", address(emissionManager))
//         );
//         emissionManager.setRewardsController(address(incentives));

//         // 12. Update flash loan premium to zero.

//         poolConfigurator.updateFlashloanPremiumTotal(0);    // Flash loans are free

//         // 13. Deploy data provider contracts.

//         proxy                   = IEACAggregatorProxy(config.readAddress(".nativeTokenOracle"));
//         uiPoolDataProvider      = new UiPoolDataProviderV3(proxy, proxy);
//         uiIncentiveDataProvider = new UiIncentiveDataProviderV3();
//         wethGateway             = new WrappedTokenGatewayV3(config.readAddress(".nativeToken"), admin, IPool(address(pool)));
//         walletBalanceProvider   = new WalletBalanceProvider();

//         // 14. Set up oracle.

//         address[] memory assets;
//         address[] memory oracles;
//         aaveOracle = new AaveOracle(
//             poolAddressesProvider,
//             assets,
//             oracles,
//             address(0),
//             address(0),  // USD
//             1e8
//         );
//         poolAddressesProvider.setPriceOracle(address(aaveOracle));

//         // 15. Transfer all ownership from deployer to admin

//         aclManager.addEmergencyAdmin(admin);
//         aclManager.addPoolAdmin(admin);
//         aclManager.removePoolAdmin(deployer);
//         aclManager.grantRole(aclManager.DEFAULT_ADMIN_ROLE(), admin);
//         aclManager.revokeRole(aclManager.DEFAULT_ADMIN_ROLE(), deployer);

//         poolAddressesProvider.setACLAdmin(admin);
//         poolAddressesProvider.transferOwnership(admin);

//         registry.transferOwnership(admin);
//         emissionManager.transferOwnership(admin);

//         vm.stopBroadcast();

//         ScriptTools.exportContract(instanceId, "aTokenImpl",      address(aTokenImpl));
//         ScriptTools.exportContract(instanceId, "aaveOracle",      address(aaveOracle));
//         ScriptTools.exportContract(instanceId, "aclManager",      address(aclManager));
//         ScriptTools.exportContract(instanceId, "admin",           address(admin));
//         ScriptTools.exportContract(instanceId, "deployer",        address(deployer));
//         ScriptTools.exportContract(instanceId, "emissionManager", address(emissionManager));
//         ScriptTools.exportContract(instanceId, "incentives",      address(incentives));
//         ScriptTools.exportContract(instanceId, "incentivesImpl",  address(rewardsController));
//         ScriptTools.exportContract(instanceId, "pool",            address(pool));

//         ScriptTools.exportContract(instanceId, "poolAddressesProvider",         address(poolAddressesProvider));
//         ScriptTools.exportContract(instanceId, "poolAddressesProviderRegistry", address(registry));

//         ScriptTools.exportContract(instanceId, "poolConfigurator",        address(poolConfigurator));
//         ScriptTools.exportContract(instanceId, "poolConfiguratorImpl",    address(poolConfiguratorImpl));
//         ScriptTools.exportContract(instanceId, "poolImpl",                address(poolImpl));
//         ScriptTools.exportContract(instanceId, "protocolDataProvider",    address(protocolDataProvider));
//         ScriptTools.exportContract(instanceId, "stableDebtTokenImpl",     address(stableDebtTokenImpl));
//         ScriptTools.exportContract(instanceId, "treasury",                address(treasury));
//         ScriptTools.exportContract(instanceId, "treasuryController",      address(treasuryController));
//         ScriptTools.exportContract(instanceId, "treasuryImpl",            address(treasuryImpl));
//         ScriptTools.exportContract(instanceId, "uiIncentiveDataProvider", address(uiIncentiveDataProvider));
//         ScriptTools.exportContract(instanceId, "uiPoolDataProvider",      address(uiPoolDataProvider));
//         ScriptTools.exportContract(instanceId, "variableDebtTokenImpl",   address(variableDebtTokenImpl));
//         ScriptTools.exportContract(instanceId, "walletBalanceProvider",   address(walletBalanceProvider));
//         ScriptTools.exportContract(instanceId, "wethGateway",             address(wethGateway));
//     }

//     function createCollector(address _admin) internal returns (Collector collector, address impl) {
//         InitializableAdminUpgradeabilityProxy collectorProxy = new InitializableAdminUpgradeabilityProxy();
//         collector = Collector(address(collectorProxy));
//         impl = address(collectorImpl);
//         collectorProxy.initialize(
//             address(collectorImpl),
//             _admin,
//             abi.encodeWithSignature("initialize(address)", address(treasuryController))
//         );
//     }

// }
