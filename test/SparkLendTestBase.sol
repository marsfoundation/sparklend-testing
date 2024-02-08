// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { VmSafe } from "forge-std/Vm.sol";

import { AaveOracle }                               from "aave-v3-core/contracts/misc/AaveOracle.sol";
import { AaveProtocolDataProvider as DataProvider } from "aave-v3-core/contracts/misc/AaveProtocolDataProvider.sol";

import { ACLManager }                    from "aave-v3-core/contracts/protocol/configuration/ACLManager.sol";
import { PoolAddressesProvider }         from "aave-v3-core/contracts/protocol/configuration/PoolAddressesProvider.sol";
import { PoolAddressesProviderRegistry } from "aave-v3-core/contracts/protocol/configuration/PoolAddressesProviderRegistry.sol";

import { Pool }             from "aave-v3-core/contracts/protocol/pool/Pool.sol";
import { PoolConfigurator } from "aave-v3-core/contracts/protocol/pool/PoolConfigurator.sol";

import { ConfiguratorInputTypes } from "aave-v3-core/contracts/protocol/libraries/types/ConfiguratorInputTypes.sol";
import { DataTypes }              from "aave-v3-core/contracts/protocol/libraries/types/DataTypes.sol";

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
// TODO: In dedicated AToken tests, explore UserState mapping so index can be asserted.

contract SparkLendTestBase is Test {

    // 3.65 days in seconds - gives clean numbers for testing (1% of APR)
    uint256 constant WARP_TIME = 365 days / 100;

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

    AToken aBorrowAsset;
    AToken aCollateralAsset;

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
                optimalUsageRatio:      0.80e27,
                baseVariableBorrowRate: 0.05e27,
                variableRateSlope1:     0.02e27,
                variableRateSlope2:     0.3e27
            }));

        collateralAsset = new MockERC20("Collateral Asset", "COLL", 18);
        borrowAsset     = new MockERC20("Borrow Asset",     "BRRW", 18);

        _initReserve(IERC20(address(collateralAsset)), strategy);
        _initReserve(IERC20(address(borrowAsset)),     strategy);

        _setUpMockOracle(address(collateralAsset), int256(1e8));
        _setUpMockOracle(address(borrowAsset),     int256(1e8));

        aBorrowAsset     = AToken(_getAToken(address(borrowAsset)));
        aCollateralAsset = AToken(_getAToken(address(collateralAsset)));

        vm.label(address(borrowAsset),      "borrowAsset");
        vm.label(address(collateralAsset),  "collateralAsset");
        vm.label(address(aBorrowAsset),     "aBorrowAsset");
        vm.label(address(aCollateralAsset), "aCollateralAsset");
        vm.label(address(pool),             "pool");
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
                provider:               poolAddressesProvider,
                optimalUsageRatio:      0.80e27,
                baseVariableBorrowRate: 0.05e27,
                variableRateSlope1:     0.02e27,
                variableRateSlope2:     0.30e27
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
    /*** Utility calculation functions                                                          ***/
    /**********************************************************************************************/

    function _getCompoundedNormalizedInterest(uint256 rate, uint256 timeDelta)
        internal pure returns (uint256 interestRate)
    {
        // interest = 1 + nx + (n/2)(n-1)x^2 + (n/6)(n-1)(n-2)x^3
        // where n = timeDelta and x = rate / 365 days

        uint256 term1 = 1e27;
        uint256 term2 = rate * timeDelta / 365 days;
        uint256 term3 = _rateExp(rate, 2) * timeDelta * (timeDelta - 1) / 2;
        uint256 term4 = _rateExp(rate, 3) * timeDelta * (timeDelta - 1) * (timeDelta - 2) / 6;

        interestRate = term1 + term2 + term3 + term4;
    }

    function _rateExp(uint256 x, uint256 n) internal pure returns (uint256 result) {
        result = x / 365 days;

        for (uint256 i = 1; i < n; i++) {
            result = result * x / 1e27 / 365 days;
        }
    }

    function _getUpdatedRates(
        uint256 borrowed,
        uint256 totalValue,
        uint256 baseRate,
        uint256 slope1,
        uint256 optimizedUtilization
    )
        internal pure returns (uint256, uint256)
    {
        uint256 borrowRatio   = borrowed * 1e27 / totalValue;
        uint256 borrowRate    = baseRate + slope1 * borrowRatio / optimizedUtilization;
        uint256 liquidityRate = borrowRate * borrowRatio / 1e27;

        return (borrowRate, liquidityRate);
    }

    /**********************************************************************************************/
    /*** Utility functions                                                                      ***/
    /**********************************************************************************************/

    function _getUpdatedRates(uint256 borrowed, uint256 supplied)
        internal pure returns (uint256, uint256)
    {
        return _getUpdatedRates(borrowed, supplied, 0.05e27, 0.02e27, 0.8e27);
    }

    /**********************************************************************************************/
    /*** Assertion helper functions                                                             ***/
    /**********************************************************************************************/

    struct AssertPoolReserveStateParams {
        uint256 liquidityIndex;
        uint256 currentLiquidityRate;
        uint256 variableBorrowIndex;
        uint256 currentVariableBorrowRate;
        uint256 currentStableBorrowRate;
        uint256 lastUpdateTimestamp;
        uint256 accruedToTreasury;
        uint256 unbacked;
    }

    function _assertPoolReserveState(AssertPoolReserveStateParams memory params) internal {

        DataTypes.ReserveData memory data = pool.getReserveData(address(collateralAsset));

        assertEq(data.liquidityIndex,            params.liquidityIndex,            "liquidityIndex");
        assertEq(data.currentLiquidityRate,      params.currentLiquidityRate,      "currentLiquidityRate");
        assertEq(data.variableBorrowIndex,       params.variableBorrowIndex,       "variableBorrowIndex");
        assertEq(data.currentVariableBorrowRate, params.currentVariableBorrowRate, "variableBorrowRate");
        assertEq(data.currentStableBorrowRate,   params.currentStableBorrowRate,   "stableBorrowRate");
        assertEq(data.lastUpdateTimestamp,       params.lastUpdateTimestamp,       "lastUpdateTimestamp");
        assertEq(data.accruedToTreasury,         params.accruedToTreasury,         "accruedToTreasury");
        assertEq(data.unbacked,                  params.unbacked,                  "unbacked");

        // NOTE: Intentionally left out the following as they do not change on user actions
        // - ReserveConfigurationMap configuration;
        // - uint16 id;
        // - address aTokenAddress;
        // - address stableDebtTokenAddress;
        // - address variableDebtTokenAddress;
        // - address interestRateStrategyAddress;
        // - uint128 isolationModeTotalDebt;
    }

    struct AssertAssetStateParams {
        address user;
        address asset;
        uint256 allowance;
        uint256 userBalance;
        uint256 aTokenBalance;
    }

    function _assertAssetState(AssertAssetStateParams memory params) internal {
        address aToken = pool.getReserveData(address(params.asset)).aTokenAddress;

        assertEq(IERC20(params.asset).allowance(params.user, address(pool)), params.allowance, "allowance");

        assertEq(IERC20(params.asset).balanceOf(params.user), params.userBalance,   "userBalance");
        assertEq(IERC20(params.asset).balanceOf(aToken),      params.aTokenBalance, "aTokenBalance");
    }

    struct AssertATokenStateParams {
        address user;
        address aToken;
        uint256 userBalance;
        uint256 totalSupply;
    }

    function _assertATokenState(AssertATokenStateParams memory params) internal {
        assertEq(IERC20(params.aToken).balanceOf(params.user), params.userBalance, "userBalance");
        assertEq(IERC20(params.aToken).totalSupply(),          params.totalSupply, "totalSupply");
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
