// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { BaseImmutableAdminUpgradeabilityProxy } 
    from "sparklend-v1-core/contracts/protocol/libraries/aave-upgradeability/BaseImmutableAdminUpgradeabilityProxy.sol";

import { DataTypes } from "sparklend-v1-core/contracts/protocol/libraries/types/DataTypes.sol";
import { Errors }    from "sparklend-v1-core/contracts/protocol/libraries/helpers/Errors.sol";

import { SparkLendTestBase } from "test/SparkLendTestBase.sol";

contract PoolACLTests is SparkLendTestBase {

    address public A_TOKEN;
    address public BRIDGE;
    address public POOL_ADDRESSES_PROVIDER;
    address public POOL_ADMIN;
    address public POOL_CONFIGURATOR;

    function setUp() public override {
        super.setUp();
        
        A_TOKEN                 = address(aBorrowAsset);
        BRIDGE                  = makeAddr("bridge");
        POOL_ADDRESSES_PROVIDER = address(poolAddressesProvider);
        POOL_ADMIN              = admin;
        POOL_CONFIGURATOR       = address(poolConfigurator);

        bytes32 bridgeRole = keccak256('BRIDGE');
        
        vm.prank(admin);
        aclManager.grantRole(bridgeRole, BRIDGE);
    }

    /**********************************************************************************************/
    /*** Pool Admin ACL tests                                                                   ***/
    /**********************************************************************************************/

    function test_rescueTokens_poolAdminACL() public {
        vm.expectRevert(bytes(Errors.CALLER_NOT_POOL_ADMIN));
        pool.rescueTokens(address(borrowAsset), address(this), 100);

        // Passes ACL check in `onlyPoolAdmin`
        vm.prank(POOL_ADMIN);
        vm.expectRevert(stdError.arithmeticError);
        pool.rescueTokens(address(borrowAsset), address(this), 100);
    }

    /**********************************************************************************************/
    /*** Pool Configurator ACL tests                                                            ***/
    /**********************************************************************************************/

    function test_configureEModeCategory_poolConfiguratorACL() public {
        DataTypes.EModeCategory memory eModeCategory = DataTypes.EModeCategory({
            ltv:                  50_00,
            liquidationThreshold: 50_00,
            liquidationBonus:     100_01,
            priceSource:          address(0),
            label:                "emode1"
        });

        vm.expectRevert(bytes(Errors.CALLER_NOT_POOL_CONFIGURATOR));
        pool.configureEModeCategory(1, eModeCategory);

        vm.prank(POOL_CONFIGURATOR);
        pool.configureEModeCategory(1, eModeCategory);
    }

    function test_dropReserve_poolConfiguratorACL() public {
        vm.expectRevert(bytes(Errors.CALLER_NOT_POOL_CONFIGURATOR));
        pool.dropReserve(address(borrowAsset));

        vm.prank(POOL_CONFIGURATOR);
        pool.dropReserve(address(borrowAsset));
    }

    function test_initReserve_poolConfiguratorACL() public {
        vm.expectRevert(bytes(Errors.CALLER_NOT_POOL_CONFIGURATOR));
        pool.initReserve(
            address(borrowAsset),
            address(0),
            address(0),
            address(0),
            address(0)
        );

        // Passes ACL check in `onlyPoolConfigurator`
        vm.prank(POOL_CONFIGURATOR);
        vm.expectRevert(bytes(Errors.RESERVE_ALREADY_INITIALIZED));
        pool.initReserve(
            address(borrowAsset),
            address(0),
            address(0),
            address(0),
            address(0)
        );
    }

    function test_setConfiguration_poolConfiguratorACL() public {
        DataTypes.ReserveConfigurationMap memory config = DataTypes.ReserveConfigurationMap({
            data: 0
        });

        vm.expectRevert(bytes(Errors.CALLER_NOT_POOL_CONFIGURATOR));
        pool.setConfiguration(address(borrowAsset), config);

        vm.prank(POOL_CONFIGURATOR);
        pool.setConfiguration(address(borrowAsset), config);
    }

    function test_setReserveInterestRateStrategyAddress_poolConfiguratorACL() public {
        vm.expectRevert(bytes(Errors.CALLER_NOT_POOL_CONFIGURATOR));
        pool.setReserveInterestRateStrategyAddress(address(borrowAsset), address(0));

        vm.prank(POOL_CONFIGURATOR);
        pool.setReserveInterestRateStrategyAddress(address(borrowAsset), address(0));
    }

    function test_updateFlashloanPremiums_poolConfiguratorACL() public {
        vm.expectRevert(bytes(Errors.CALLER_NOT_POOL_CONFIGURATOR));
        pool.updateFlashloanPremiums(100, 100);

        vm.prank(POOL_CONFIGURATOR);
        pool.updateFlashloanPremiums(100, 100);
    }

    function test_resetIsolationModeTotalDebt_poolConfiguratorACL() public {
        vm.expectRevert(bytes(Errors.CALLER_NOT_POOL_CONFIGURATOR));
        pool.resetIsolationModeTotalDebt(address(borrowAsset));

        vm.prank(POOL_CONFIGURATOR);
        pool.resetIsolationModeTotalDebt(address(borrowAsset));
    }

    function test_updateBridgeProtocolFee_poolConfiguratorACL() public {
        vm.expectRevert(bytes(Errors.CALLER_NOT_POOL_CONFIGURATOR));
        pool.updateBridgeProtocolFee(100);

        vm.prank(POOL_CONFIGURATOR);
        pool.updateBridgeProtocolFee(100);
    }

    /**********************************************************************************************/
    /*** Bridge ACL tests                                                                       ***/
    /**********************************************************************************************/

    function test_mintUnbacked_bridgeACL() public {
        vm.expectRevert(bytes(Errors.CALLER_NOT_BRIDGE));
        pool.mintUnbacked(address(borrowAsset), 100, address(this), 1);

        // Passes ACL check in `onlyBridge`
        vm.prank(BRIDGE);
        vm.expectRevert(bytes(Errors.UNBACKED_MINT_CAP_EXCEEDED));
        pool.mintUnbacked(address(borrowAsset), 100, address(this), 1);
    }

    function test_backUnbacked_bridgeACL() public {
        vm.expectRevert(bytes(Errors.CALLER_NOT_BRIDGE));
        pool.backUnbacked(address(borrowAsset), 100, 1);

        // Passes ACL check in `onlyBridge`
        vm.prank(BRIDGE);
        vm.expectRevert(bytes(""));  // EVM revert in BridgeLogic library
        pool.backUnbacked(address(borrowAsset), 100, 1);
    }

    /**********************************************************************************************/
    /*** AToken ACL tests                                                                       ***/
    /**********************************************************************************************/

    function test_finalizeTransfer_aTokenACL() public {
        vm.expectRevert(bytes(Errors.CALLER_NOT_ATOKEN));
        pool.finalizeTransfer(address(borrowAsset), address(this), address(this), 100, 100, 100);

        vm.prank(A_TOKEN);
        pool.finalizeTransfer(address(borrowAsset), address(this), address(this), 100, 100, 100);
    }

    /**********************************************************************************************/
    /*** Pool Addresses Provider Upgradeability ACL tests                                       ***/
    /**********************************************************************************************/

    function test_upgradeTo_upgradeabilityACL() public {
        BaseImmutableAdminUpgradeabilityProxy poolProxy 
            = BaseImmutableAdminUpgradeabilityProxy(payable(address(pool)));

        // Routes to fallback which EVM reverts when selector doesn't match on pool implementation
        vm.expectRevert(bytes(""));
        poolProxy.upgradeTo(address(borrowAsset));  // Use an address with code

        vm.prank(POOL_ADDRESSES_PROVIDER);
        poolProxy.upgradeTo(address(borrowAsset));  // Use an address with code
    }

    // NOTE: This function signature does NOT match what's on mainnet for the Pool proxy.
    // TODO: Investigate this.
    function test_upgradeToAndCall_upgradeabilityACL() public {
        BaseImmutableAdminUpgradeabilityProxy poolProxy 
            = BaseImmutableAdminUpgradeabilityProxy(payable(address(pool)));

        // Routes to fallback which EVM reverts when selector doesn't match on pool implementation
        vm.expectRevert(bytes(""));
        poolProxy.upgradeToAndCall(address(borrowAsset), abi.encodeWithSignature("totalSupply()"));  

        vm.prank(POOL_ADDRESSES_PROVIDER);
        poolProxy.upgradeToAndCall(address(borrowAsset), abi.encodeWithSignature("totalSupply()"));  
    }
    
}
