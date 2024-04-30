// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { BaseImmutableAdminUpgradeabilityProxy }
    from "sparklend-v1-core/contracts/protocol/libraries/aave-upgradeability/BaseImmutableAdminUpgradeabilityProxy.sol";

import { ConfiguratorInputTypes } from "sparklend-v1-core/contracts/protocol/libraries/types/ConfiguratorInputTypes.sol";

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

contract PoolConfiguratorACLTests is SparkLendTestBase {

    address public ASSET_LISTING_ADMIN;
    address public EMERGENCY_ADMIN;
    address public POOL_ADMIN;
    address public RISK_ADMIN;

    function setUp() public override {
        super.setUp();

        // NOTE: AssetListingAdmin is not used on mainnet so adding to this setUp instead of base
        ASSET_LISTING_ADMIN = makeAddr("assetListingAdmin");
        EMERGENCY_ADMIN     = emergencyAdmin;
        POOL_ADMIN          = admin;
        RISK_ADMIN          = riskAdmin;

        vm.prank(admin);
        aclManager.addAssetListingAdmin(ASSET_LISTING_ADMIN);
    }

    /**********************************************************************************************/
    /*** Only Pool Admin ACL tests                                                              ***/
    /**********************************************************************************************/

    function test_dropReserve_onlyPoolAdminACL() public {
        vm.expectRevert(bytes(Errors.CALLER_NOT_POOL_ADMIN));
        poolConfigurator.dropReserve(address(borrowAsset));

        // Other admins should fail

        vm.prank(ASSET_LISTING_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_POOL_ADMIN));
        poolConfigurator.dropReserve(address(borrowAsset));

        vm.prank(EMERGENCY_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_POOL_ADMIN));
        poolConfigurator.dropReserve(address(borrowAsset));

        vm.prank(RISK_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_POOL_ADMIN));
        poolConfigurator.dropReserve(address(borrowAsset));

        // PoolAdmin passes

        vm.prank(POOL_ADMIN);
        poolConfigurator.dropReserve(address(borrowAsset));
    }

    function test_updateAToken_onlyPoolAdminACL() public {
        ConfiguratorInputTypes.UpdateATokenInput memory input
            = ConfiguratorInputTypes.UpdateATokenInput({
                asset:                address(borrowAsset),
                treasury:             treasury,
                incentivesController: address(0),
                name:                 "aToken",
                symbol:               "aToken",
                implementation:       address(borrowAsset),  // Address with code
                params :              abi.encode("")
            });

        vm.expectRevert(bytes(Errors.CALLER_NOT_POOL_ADMIN));
        poolConfigurator.updateAToken(input);

        // Other admins should fail

        vm.prank(ASSET_LISTING_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_POOL_ADMIN));
        poolConfigurator.updateAToken(input);

        vm.prank(EMERGENCY_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_POOL_ADMIN));
        poolConfigurator.updateAToken(input);

        vm.prank(RISK_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_POOL_ADMIN));
        poolConfigurator.updateAToken(input);

        // PoolAdmin passes

        // Passes ACL check in `onlyPoolAdmin`
        vm.prank(POOL_ADMIN);
        vm.expectRevert(bytes(""));  // EVM revert in ConfiguratorLogic library
        poolConfigurator.updateAToken(input);
    }

    function test_updateStableDebtToken_onlyPoolAdminACL() public {
        ConfiguratorInputTypes.UpdateDebtTokenInput memory input
            = ConfiguratorInputTypes.UpdateDebtTokenInput({
                asset:                address(borrowAsset),
                incentivesController: address(0),
                name:                 "aToken",
                symbol:               "aToken",
                implementation:       address(borrowAsset),  // Address with code
                params :              abi.encode("")
            });

        vm.expectRevert(bytes(Errors.CALLER_NOT_POOL_ADMIN));
        poolConfigurator.updateStableDebtToken(input);

        // Other admins should fail

        vm.prank(ASSET_LISTING_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_POOL_ADMIN));
        poolConfigurator.updateStableDebtToken(input);

        vm.prank(EMERGENCY_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_POOL_ADMIN));
        poolConfigurator.updateStableDebtToken(input);

        vm.prank(RISK_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_POOL_ADMIN));
        poolConfigurator.updateStableDebtToken(input);

        // PoolAdmin passes

        // Passes ACL check in `onlyPoolAdmin`
        vm.prank(POOL_ADMIN);
        vm.expectRevert(bytes(""));  // EVM revert in ConfiguratorLogic library
        poolConfigurator.updateStableDebtToken(input);
    }

    function test_updateVariableDebtToken_onlyPoolAdminACL() public {
        ConfiguratorInputTypes.UpdateDebtTokenInput memory input
            = ConfiguratorInputTypes.UpdateDebtTokenInput({
                asset:                address(borrowAsset),
                incentivesController: address(0),
                name:                 "aToken",
                symbol:               "aToken",
                implementation:       address(borrowAsset),  // Address with code
                params :              abi.encode("")
            });

        vm.expectRevert(bytes(Errors.CALLER_NOT_POOL_ADMIN));
        poolConfigurator.updateVariableDebtToken(input);

        // Other admins should fail

        vm.prank(ASSET_LISTING_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_POOL_ADMIN));
        poolConfigurator.updateVariableDebtToken(input);

        vm.prank(EMERGENCY_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_POOL_ADMIN));
        poolConfigurator.updateVariableDebtToken(input);

        vm.prank(RISK_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_POOL_ADMIN));
        poolConfigurator.updateVariableDebtToken(input);

        // PoolAdmin passes

        // Passes ACL check in `onlyPoolAdmin`
        vm.prank(POOL_ADMIN);
        vm.expectRevert(bytes(""));  // EVM revert in ConfiguratorLogic library
        poolConfigurator.updateVariableDebtToken(input);
    }

    function test_setReserveActive_onlyPoolAdminACL() public {
        vm.expectRevert(bytes(Errors.CALLER_NOT_POOL_ADMIN));
        poolConfigurator.setReserveActive(address(borrowAsset), true);

        // Other admins should fail

        vm.prank(ASSET_LISTING_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_POOL_ADMIN));
        poolConfigurator.setReserveActive(address(borrowAsset), true);

        vm.prank(EMERGENCY_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_POOL_ADMIN));
        poolConfigurator.setReserveActive(address(borrowAsset), true);

        vm.prank(RISK_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_POOL_ADMIN));
        poolConfigurator.setReserveActive(address(borrowAsset), true);

        // PoolAdmin passes

        vm.prank(POOL_ADMIN);
        poolConfigurator.setReserveActive(address(borrowAsset), true);
    }

    function test_updateBridgeProtocolFee_onlyPoolAdminACL() public {
        vm.expectRevert(bytes(Errors.CALLER_NOT_POOL_ADMIN));
        poolConfigurator.updateBridgeProtocolFee(100);

        // Other admins should fail

        vm.prank(ASSET_LISTING_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_POOL_ADMIN));
        poolConfigurator.updateBridgeProtocolFee(100);

        vm.prank(EMERGENCY_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_POOL_ADMIN));
        poolConfigurator.updateBridgeProtocolFee(100);

        vm.prank(RISK_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_POOL_ADMIN));
        poolConfigurator.updateBridgeProtocolFee(100);

        // PoolAdmin passes

        vm.prank(POOL_ADMIN);
        poolConfigurator.updateBridgeProtocolFee(100);
    }

    function test_updateFlashloanPremiumTotal_onlyPoolAdminACL() public {
        vm.expectRevert(bytes(Errors.CALLER_NOT_POOL_ADMIN));
        poolConfigurator.updateFlashloanPremiumTotal(100);

        // Other admins should fail

        vm.prank(ASSET_LISTING_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_POOL_ADMIN));
        poolConfigurator.updateFlashloanPremiumTotal(100);

        vm.prank(EMERGENCY_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_POOL_ADMIN));
        poolConfigurator.updateFlashloanPremiumTotal(100);

        vm.prank(RISK_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_POOL_ADMIN));
        poolConfigurator.updateFlashloanPremiumTotal(100);

        // PoolAdmin passes

        vm.prank(POOL_ADMIN);
        poolConfigurator.updateFlashloanPremiumTotal(100);
    }

    function test_updateFlashloanPremiumToProtocol_onlyPoolAdminACL() public {
        vm.expectRevert(bytes(Errors.CALLER_NOT_POOL_ADMIN));
        poolConfigurator.updateFlashloanPremiumToProtocol(100);

        // Other admins should fail

        vm.prank(ASSET_LISTING_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_POOL_ADMIN));
        poolConfigurator.updateFlashloanPremiumToProtocol(100);

        vm.prank(EMERGENCY_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_POOL_ADMIN));
        poolConfigurator.updateFlashloanPremiumToProtocol(100);

        vm.prank(RISK_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_POOL_ADMIN));
        poolConfigurator.updateFlashloanPremiumToProtocol(100);

        // PoolAdmin passes

        vm.prank(POOL_ADMIN);
        poolConfigurator.updateFlashloanPremiumToProtocol(100);
    }

    /**********************************************************************************************/
    /*** Only Emergency Admin ACL tests                                                         ***/
    /**********************************************************************************************/

    function test_setPoolPause_onlyEmergencyAdminACL() public {
        vm.expectRevert(bytes(Errors.CALLER_NOT_EMERGENCY_ADMIN));
        poolConfigurator.setPoolPause(true);

        // Other admins should fail

        vm.prank(ASSET_LISTING_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_EMERGENCY_ADMIN));
        poolConfigurator.setPoolPause(true);

        vm.prank(POOL_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_EMERGENCY_ADMIN));
        poolConfigurator.setPoolPause(true);

        vm.prank(RISK_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_EMERGENCY_ADMIN));
        poolConfigurator.setPoolPause(true);

        // EmergencyAdmin passes

        vm.prank(EMERGENCY_ADMIN);
        poolConfigurator.setPoolPause(true);
    }

    /**********************************************************************************************/
    /*** Emergency Admin or Pool Admin ACL tests                                                ***/
    /**********************************************************************************************/

    function test_setReservePause_emergencyAdminOrPoolAdminACL() public {
        vm.expectRevert(bytes(Errors.CALLER_NOT_POOL_OR_EMERGENCY_ADMIN));
        poolConfigurator.setReservePause(address(borrowAsset), true);

        // Other admins should fail

        vm.prank(ASSET_LISTING_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_POOL_OR_EMERGENCY_ADMIN));
        poolConfigurator.setReservePause(address(borrowAsset), true);

        vm.prank(RISK_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_POOL_OR_EMERGENCY_ADMIN));
        poolConfigurator.setReservePause(address(borrowAsset), true);

        // EmergencyAdmin and PoolAdmin pass

        vm.prank(EMERGENCY_ADMIN);
        poolConfigurator.setReservePause(address(borrowAsset), true);

        vm.prank(POOL_ADMIN);
        poolConfigurator.setReservePause(address(borrowAsset), true);
    }

    /**********************************************************************************************/
    /*** Asset Listing Admin or Pool Admin ACL tests                                            ***/
    /**********************************************************************************************/

    function test_initReserves_assetListingAdminOrPoolAdminACL() public {
        ConfiguratorInputTypes.InitReserveInput[] memory input
            = new ConfiguratorInputTypes.InitReserveInput[](1);

        input[0] = ConfiguratorInputTypes.InitReserveInput({
            aTokenImpl:                  address(borrowAsset),  // Address with code
            stableDebtTokenImpl:         address(borrowAsset),  // Address with code
            variableDebtTokenImpl:       address(borrowAsset),  // Address with code
            underlyingAssetDecimals:     18,
            interestRateStrategyAddress: address(borrowAsset),  // Address with code
            underlyingAsset:             address(borrowAsset),  // Address with code
            treasury:                    treasury,
            incentivesController:        address(0),
            aTokenName:                  "aToken",
            aTokenSymbol:                "aToken",
            variableDebtTokenName:       "vdToken",
            variableDebtTokenSymbol:     "vdToken",
            stableDebtTokenName:         "sdToken",
            stableDebtTokenSymbol:       "sdToken",
            params:                      abi.encode("")
        });

        vm.expectRevert(bytes(Errors.CALLER_NOT_ASSET_LISTING_OR_POOL_ADMIN));
        poolConfigurator.initReserves(input);

        // Other admins should fail

        vm.prank(EMERGENCY_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_ASSET_LISTING_OR_POOL_ADMIN));
        poolConfigurator.initReserves(input);

        vm.prank(RISK_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_ASSET_LISTING_OR_POOL_ADMIN));
        poolConfigurator.initReserves(input);

        // AssetListingAdmin and PoolAdmin pass ACL check in `onlyAssetListingOrPoolAdmin`

        vm.prank(ASSET_LISTING_ADMIN);
        vm.expectRevert(bytes(""));  // EVM revert in ConfiguratorLogic library
        poolConfigurator.initReserves(input);

        vm.prank(POOL_ADMIN);
        vm.expectRevert(bytes(""));  // EVM revert in ConfiguratorLogic library
        poolConfigurator.initReserves(input);
    }

    /**********************************************************************************************/
    /*** Risk Admin or Pool Admin ACL tests                                                     ***/
    /**********************************************************************************************/

    function test_setReserveBorrowing_riskAdminOrPoolAdminACL() public {
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.setReserveBorrowing(address(borrowAsset), true);

        // Other admins should fail

        vm.prank(ASSET_LISTING_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.setReserveBorrowing(address(borrowAsset), true);

        vm.prank(EMERGENCY_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.setReserveBorrowing(address(borrowAsset), true);

        // RiskAdmin and PoolAdmin pass

        vm.prank(POOL_ADMIN);
        poolConfigurator.setReserveBorrowing(address(borrowAsset), true);

        vm.prank(RISK_ADMIN);
        poolConfigurator.setReserveBorrowing(address(borrowAsset), true);
    }

    function test_configureReserveAsCollateral_riskAdminOrPoolAdminACL() public {
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.configureReserveAsCollateral(address(borrowAsset), 50_00, 50_00, 101_00);

        // Other admins should fail

        vm.prank(ASSET_LISTING_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.configureReserveAsCollateral(address(borrowAsset), 50_00, 50_00, 101_00);

        vm.prank(EMERGENCY_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.configureReserveAsCollateral(address(borrowAsset), 50_00, 50_00, 101_00);

        // RiskAdmin and PoolAdmin pass

        vm.prank(POOL_ADMIN);
        poolConfigurator.configureReserveAsCollateral(address(borrowAsset), 50_00, 50_00, 101_00);

        vm.prank(RISK_ADMIN);
        poolConfigurator.configureReserveAsCollateral(address(borrowAsset), 50_00, 50_00, 101_00);
    }

    function test_setReserveStableRateBorrowing_riskAdminOrPoolAdminACL() public {
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.setReserveStableRateBorrowing(address(borrowAsset), true);

        // Other admins should fail

        vm.prank(ASSET_LISTING_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.setReserveStableRateBorrowing(address(borrowAsset), true);

        vm.prank(EMERGENCY_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.setReserveStableRateBorrowing(address(borrowAsset), true);

        // RiskAdmin and PoolAdmin pass ACL check in `onlyRiskOrPoolAdmins`

        vm.prank(POOL_ADMIN);
        vm.expectRevert(bytes(Errors.BORROWING_NOT_ENABLED));
        poolConfigurator.setReserveStableRateBorrowing(address(borrowAsset), true);

        vm.prank(RISK_ADMIN);
        vm.expectRevert(bytes(Errors.BORROWING_NOT_ENABLED));
        poolConfigurator.setReserveStableRateBorrowing(address(borrowAsset), true);
    }

    function test_setReserveFlashLoaning_riskAdminOrPoolAdminACL() public {
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.setReserveFlashLoaning(address(borrowAsset), true);

        // Other admins should fail

        vm.prank(ASSET_LISTING_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.setReserveFlashLoaning(address(borrowAsset), true);

        vm.prank(EMERGENCY_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.setReserveFlashLoaning(address(borrowAsset), true);

        // RiskAdmin and PoolAdmin pass

        vm.prank(POOL_ADMIN);
        poolConfigurator.setReserveFlashLoaning(address(borrowAsset), true);

        vm.prank(RISK_ADMIN);
        poolConfigurator.setReserveFlashLoaning(address(borrowAsset), true);
    }

    function test_setReserveFreeze_riskAdminOrPoolAdminACL() public {
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.setReserveFreeze(address(borrowAsset), true);

        // Other admins should fail

        vm.prank(ASSET_LISTING_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.setReserveFreeze(address(borrowAsset), true);

        vm.prank(EMERGENCY_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.setReserveFreeze(address(borrowAsset), true);

        // RiskAdmin and PoolAdmin pass

        vm.prank(POOL_ADMIN);
        poolConfigurator.setReserveFreeze(address(borrowAsset), true);

        vm.prank(RISK_ADMIN);
        poolConfigurator.setReserveFreeze(address(borrowAsset), true);
    }

    function test_setBorrowableInIsolation_riskAdminOrPoolAdminACL() public {
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.setBorrowableInIsolation(address(borrowAsset), true);

        // Other admins should fail

        vm.prank(ASSET_LISTING_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.setBorrowableInIsolation(address(borrowAsset), true);

        vm.prank(EMERGENCY_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.setBorrowableInIsolation(address(borrowAsset), true);

        // RiskAdmin and PoolAdmin pass

        vm.prank(POOL_ADMIN);
        poolConfigurator.setBorrowableInIsolation(address(borrowAsset), true);

        vm.prank(RISK_ADMIN);
        poolConfigurator.setBorrowableInIsolation(address(borrowAsset), true);
    }

    function test_setReserveFactor_riskAdminOrPoolAdminACL() public {
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.setReserveFactor(address(borrowAsset), 1_00);

        // Other admins should fail

        vm.prank(ASSET_LISTING_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.setReserveFactor(address(borrowAsset), 1_00);

        vm.prank(EMERGENCY_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.setReserveFactor(address(borrowAsset), 1_00);

        // RiskAdmin and PoolAdmin pass

        vm.prank(POOL_ADMIN);
        poolConfigurator.setReserveFactor(address(borrowAsset), 1_00);

        vm.prank(RISK_ADMIN);
        poolConfigurator.setReserveFactor(address(borrowAsset), 1_00);
    }

    function test_setDebtCeiling_riskAdminOrPoolAdminACL() public {
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.setDebtCeiling(address(borrowAsset), 500_000_00);

        // Other admins should fail

        vm.prank(ASSET_LISTING_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.setDebtCeiling(address(borrowAsset), 500_000_00);

        vm.prank(EMERGENCY_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.setDebtCeiling(address(borrowAsset), 500_000_00);

        // RiskAdmin and PoolAdmin pass

        vm.prank(POOL_ADMIN);
        poolConfigurator.setDebtCeiling(address(borrowAsset), 500_000_00);

        vm.prank(RISK_ADMIN);
        poolConfigurator.setDebtCeiling(address(borrowAsset), 500_000_00);
    }

    function test_setSiloedBorrowing_riskAdminOrPoolAdminACL() public {
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.setSiloedBorrowing(address(borrowAsset), true);

        // Other admins should fail

        vm.prank(ASSET_LISTING_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.setSiloedBorrowing(address(borrowAsset), true);

        vm.prank(EMERGENCY_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.setSiloedBorrowing(address(borrowAsset), true);

        // RiskAdmin and PoolAdmin pass

        vm.prank(POOL_ADMIN);
        poolConfigurator.setSiloedBorrowing(address(borrowAsset), true);

        vm.prank(RISK_ADMIN);
        poolConfigurator.setSiloedBorrowing(address(borrowAsset), true);
    }

    function test_setBorrowCap_riskAdminOrPoolAdminACL() public {
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.setBorrowCap(address(borrowAsset), 500_000_00);

        // Other admins should fail

        vm.prank(ASSET_LISTING_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.setBorrowCap(address(borrowAsset), 500_000_00);

        vm.prank(EMERGENCY_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.setBorrowCap(address(borrowAsset), 500_000_00);

        // RiskAdmin and PoolAdmin pass

        vm.prank(POOL_ADMIN);
        poolConfigurator.setBorrowCap(address(borrowAsset), 500_000_00);

        vm.prank(RISK_ADMIN);
        poolConfigurator.setBorrowCap(address(borrowAsset), 500_000_00);
    }

    function test_setSupplyCap_riskAdminOrPoolAdminACL() public {
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.setSupplyCap(address(borrowAsset), 500_000_00);

        // Other admins should fail

        vm.prank(ASSET_LISTING_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.setSupplyCap(address(borrowAsset), 500_000_00);

        vm.prank(EMERGENCY_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.setSupplyCap(address(borrowAsset), 500_000_00);

        // RiskAdmin and PoolAdmin pass

        vm.prank(POOL_ADMIN);
        poolConfigurator.setSupplyCap(address(borrowAsset), 500_000_00);

        vm.prank(RISK_ADMIN);
        poolConfigurator.setSupplyCap(address(borrowAsset), 500_000_00);
    }

    function test_setLiquidationProtocolFee_riskAdminOrPoolAdminACL() public {
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.setLiquidationProtocolFee(address(borrowAsset), 5_00);

        // Other admins should fail

        vm.prank(ASSET_LISTING_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.setLiquidationProtocolFee(address(borrowAsset), 5_00);

        vm.prank(EMERGENCY_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.setLiquidationProtocolFee(address(borrowAsset), 5_00);

        // RiskAdmin and PoolAdmin pass

        vm.prank(POOL_ADMIN);
        poolConfigurator.setLiquidationProtocolFee(address(borrowAsset), 5_00);

        vm.prank(RISK_ADMIN);
        poolConfigurator.setLiquidationProtocolFee(address(borrowAsset), 5_00);
    }

    function test_setEModeCategory_riskAdminOrPoolAdminACL() public {
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.setEModeCategory(1, 50_00, 50_00, 100_01, address(0), "emode1");

        // Other admins should fail

        vm.prank(ASSET_LISTING_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.setEModeCategory(1, 50_00, 50_00, 100_01, address(0), "emode1");

        vm.prank(EMERGENCY_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.setEModeCategory(1, 50_00, 50_00, 100_01, address(0), "emode1");

        // RiskAdmin and PoolAdmin pass

        vm.prank(POOL_ADMIN);
        poolConfigurator.setEModeCategory(1, 50_00, 50_00, 100_01, address(0), "emode1");

        vm.prank(RISK_ADMIN);
        poolConfigurator.setEModeCategory(1, 50_00, 50_00, 100_01, address(0), "emode1");
    }

    function test_setAssetEModeCategory_riskAdminOrPoolAdminACL() public {
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.setAssetEModeCategory(address(borrowAsset), 1);

        // Other admins should fail

        vm.prank(ASSET_LISTING_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.setAssetEModeCategory(address(borrowAsset), 1);

        vm.prank(EMERGENCY_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.setAssetEModeCategory(address(borrowAsset), 1);

        // RiskAdmin and PoolAdmin pass ACL check in `onlyRiskOrPoolAdmins`

        vm.prank(POOL_ADMIN);
        vm.expectRevert(bytes(Errors.INVALID_EMODE_CATEGORY_ASSIGNMENT));
        poolConfigurator.setAssetEModeCategory(address(borrowAsset), 1);

        vm.prank(RISK_ADMIN);
        vm.expectRevert(bytes(Errors.INVALID_EMODE_CATEGORY_ASSIGNMENT));
        poolConfigurator.setAssetEModeCategory(address(borrowAsset), 1);
    }

    function test_setUnbackedMintCap_riskAdminOrPoolAdminACL() public {
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.setUnbackedMintCap(address(borrowAsset), 500_000_00);

        // Other admins should fail

        vm.prank(ASSET_LISTING_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.setUnbackedMintCap(address(borrowAsset), 500_000_00);

        vm.prank(EMERGENCY_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.setUnbackedMintCap(address(borrowAsset), 500_000_00);

        // RiskAdmin and PoolAdmin pass

        vm.prank(POOL_ADMIN);
        poolConfigurator.setUnbackedMintCap(address(borrowAsset), 500_000_00);

        vm.prank(RISK_ADMIN);
        poolConfigurator.setUnbackedMintCap(address(borrowAsset), 500_000_00);
    }

    function test_setReserveInterestRateStrategyAddress_riskAdminOrPoolAdminACL() public {
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.setReserveInterestRateStrategyAddress(address(borrowAsset), address(1));

        // Other admins should fail

        vm.prank(ASSET_LISTING_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.setReserveInterestRateStrategyAddress(address(borrowAsset), address(1));

        vm.prank(EMERGENCY_ADMIN);
        vm.expectRevert(bytes(Errors.CALLER_NOT_RISK_OR_POOL_ADMIN));
        poolConfigurator.setReserveInterestRateStrategyAddress(address(borrowAsset), address(1));

        // RiskAdmin and PoolAdmin pass

        vm.prank(POOL_ADMIN);
        poolConfigurator.setReserveInterestRateStrategyAddress(address(borrowAsset), address(1));

        vm.prank(RISK_ADMIN);
        poolConfigurator.setReserveInterestRateStrategyAddress(address(borrowAsset), address(1));
    }

}
