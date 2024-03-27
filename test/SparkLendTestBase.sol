// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { VmSafe } from "forge-std/Vm.sol";

import { AaveOracle }                               from "sparklend-v1-core/contracts/misc/AaveOracle.sol";
import { AaveProtocolDataProvider as DataProvider } from "sparklend-v1-core/contracts/misc/AaveProtocolDataProvider.sol";

import { ACLManager }                    from "sparklend-v1-core/contracts/protocol/configuration/ACLManager.sol";
import { PoolAddressesProvider }         from "sparklend-v1-core/contracts/protocol/configuration/PoolAddressesProvider.sol";
import { PoolAddressesProviderRegistry } from "sparklend-v1-core/contracts/protocol/configuration/PoolAddressesProviderRegistry.sol";

import { Pool }             from "sparklend-v1-core/contracts/protocol/pool/Pool.sol";
import { PoolConfigurator } from "sparklend-v1-core/contracts/protocol/pool/PoolConfigurator.sol";

import { ConfiguratorInputTypes } from "sparklend-v1-core/contracts/protocol/libraries/types/ConfiguratorInputTypes.sol";
import { DataTypes }              from "sparklend-v1-core/contracts/protocol/libraries/types/DataTypes.sol";

import { AToken }            from "sparklend-v1-core/contracts/protocol/tokenization/AToken.sol";
import { StableDebtToken }   from "sparklend-v1-core/contracts/protocol/tokenization/StableDebtToken.sol";
import { VariableDebtToken } from "sparklend-v1-core/contracts/protocol/tokenization/VariableDebtToken.sol";

import { IAaveIncentivesController }    from "sparklend-v1-core/contracts/interfaces/IAaveIncentivesController.sol";
import { IPoolAddressesProvider }       from "sparklend-v1-core/contracts/interfaces/IPoolAddressesProvider.sol";
import { IReserveInterestRateStrategy } from "sparklend-v1-core/contracts/interfaces/IReserveInterestRateStrategy.sol";

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

    address admin    = makeAddr("admin");
    address treasury = makeAddr("treasury");

    AaveOracle            aaveOracle;
    ACLManager            aclManager;
    DataProvider          protocolDataProvider;
    Pool                  pool;
    PoolAddressesProvider poolAddressesProvider;
    PoolConfigurator      poolConfigurator;

    AToken            aTokenImpl;
    Pool              poolImpl;
    PoolConfigurator  poolConfiguratorImpl;
    StableDebtToken   stableDebtTokenImpl;
    VariableDebtToken variableDebtTokenImpl;

    MockERC20 borrowAsset;
    MockERC20 collateralAsset;

    AToken aBorrowAsset;
    AToken aCollateralAsset;

    // Default values for interest rate strategies
    uint256 constant BASE_RATE     = 0.05e27;
    uint256 constant OPTIMAL_RATIO = 0.8e27;
    uint256 constant SLOPE1        = 0.02e27;
    uint256 constant SLOPE2        = 0.30e27;

    function setUp() public virtual {
        address deployer = address(this);

        poolAddressesProvider = new PoolAddressesProvider("0", deployer);

        PoolAddressesProviderRegistry registry = new PoolAddressesProviderRegistry(deployer);

        poolAddressesProvider.setACLAdmin(deployer);

        aclManager           = new ACLManager(poolAddressesProvider);
        protocolDataProvider = new DataProvider(poolAddressesProvider);

        poolConfiguratorImpl = new PoolConfigurator();
        poolConfiguratorImpl.initialize(poolAddressesProvider);

        poolImpl = new Pool(poolAddressesProvider);
        poolImpl.initialize(poolAddressesProvider);

        poolAddressesProvider.setPoolImpl(address(poolImpl));
        poolAddressesProvider.setPoolConfiguratorImpl(address(poolConfiguratorImpl));

        pool             = Pool(poolAddressesProvider.getPool());
        poolConfigurator = PoolConfigurator(poolAddressesProvider.getPoolConfigurator());

        aTokenImpl = new AToken(pool);
        aTokenImpl.initialize(
            pool,
            address(0),
            address(0),
            IAaveIncentivesController(address(0)),
            0,
            "SPTOKEN_IMPL",
            "SPTOKEN_IMPL",
            ""
        );

        stableDebtTokenImpl = new StableDebtToken(pool);
        stableDebtTokenImpl.initialize(
            pool,
            address(0),
            IAaveIncentivesController(address(0)),
            0,
            "STABLE_DEBT_TOKEN_IMPL",
            "STABLE_DEBT_TOKEN_IMPL",
            ""
        );

        variableDebtTokenImpl = new VariableDebtToken(pool);
        variableDebtTokenImpl.initialize(
            pool,
            address(0),
            IAaveIncentivesController(address(0)),
            0,
            "VARIABLE_DEBT_TOKEN_IMPL",
            "VARIABLE_DEBT_TOKEN_IMPL",
            ""
        );

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

        poolAddressesProvider.setACLManager(address(aclManager));
        poolAddressesProvider.setPoolDataProvider(address(protocolDataProvider));
        poolAddressesProvider.setPriceOracle(address(aaveOracle));

        registry.registerAddressesProvider(address(poolAddressesProvider), 1);

        aclManager.addEmergencyAdmin(admin);
        aclManager.addPoolAdmin(admin);
        aclManager.grantRole(aclManager.DEFAULT_ADMIN_ROLE(), admin);
        aclManager.revokeRole(aclManager.DEFAULT_ADMIN_ROLE(), deployer);

        poolAddressesProvider.setACLAdmin(admin);
        poolAddressesProvider.transferOwnership(admin);

        registry.transferOwnership(admin);

        IReserveInterestRateStrategy strategy
            = IReserveInterestRateStrategy(new VariableBorrowInterestRateStrategy({
                provider:               poolAddressesProvider,
                optimalUsageRatio:      OPTIMAL_RATIO,
                baseVariableBorrowRate: BASE_RATE,
                variableRateSlope1:     SLOPE1,
                variableRateSlope2:     SLOPE2
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
            treasury:                    treasury,
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
                optimalUsageRatio:      OPTIMAL_RATIO,
                baseVariableBorrowRate: BASE_RATE,
                variableRateSlope1:     SLOPE1,
                variableRateSlope2:     SLOPE2
            }));

        newCollateralAsset = address(new MockERC20("Collateral Asset", "COLL", 18));

        _initReserve(IERC20(newCollateralAsset), strategy);
        _setUpMockOracle(newCollateralAsset, int256(1e8));

        // Set LTV to 1%
        vm.prank(admin);
        poolConfigurator.configureReserveAsCollateral(newCollateralAsset, 100, 100, 100_01);
    }

    function _setCollateralDebtCeiling(address asset, uint256 ceiling) internal {
        vm.prank(admin);
        poolConfigurator.setDebtCeiling(asset, ceiling);
    }

    /**********************************************************************************************/
    /*** User helper functions                                                                  ***/
    /**********************************************************************************************/

    function _useAsCollateral(address user, address newCollateralAsset) internal {
        vm.prank(user);
        pool.setUserUseReserveAsCollateral(newCollateralAsset, true);
    }

    function _borrow(address user, address asset, uint256 amount) internal {
        vm.prank(user);
        pool.borrow(asset, amount, 2, 0, user);
    }

    function _supply(address user, address asset, uint256 amount) internal {
        vm.startPrank(user);
        MockERC20(asset).mint(user, amount);
        MockERC20(asset).approve(address(pool), amount);
        pool.supply(asset, amount, user, 0);
        vm.stopPrank();
    }

    function _repay(address user, address asset, uint256 amount) internal {
        vm.startPrank(user);
        IERC20(asset).approve(address(pool), amount);
        pool.repay(asset, amount, 2, user);
        vm.stopPrank();
    }

    function _withdraw(address user, address asset, uint256 amount) internal {
        vm.prank(user);
        pool.withdraw(asset, amount, user);
    }

    function _supplyAndUseAsCollateral(address user, address asset, uint256 amount) internal {
        _supply(user, asset, amount);
        _useAsCollateral(user, asset);
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
        if (timeDelta == 0) return 1e27;

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
        uint256 slope2,
        uint256 optimalRatio
    )
        internal pure returns (uint256, uint256)
    {
        uint256 borrowRatio = borrowed * 1e27 / totalValue;

        bool excess = borrowRatio > optimalRatio;

        uint256 slope1Ratio = excess ? 1e27 : borrowRatio * 1e27 / optimalRatio;
        uint256 slope2Ratio = excess ? (borrowRatio - optimalRatio) * 1e27 / (1e27 - optimalRatio) : 0;

        uint256 borrowRate
            = baseRate + (slope1 * slope1Ratio / 1e27) + (slope2 * slope2Ratio / 1e27);

        uint256 liquidityRate = borrowRate * borrowRatio / 1e27;

        return (borrowRate, liquidityRate);
    }

    function _getUpdatedRates(uint256 borrowed, uint256 supplied)
        internal pure returns (uint256, uint256)
    {
        return _getUpdatedRates({
            borrowed:     borrowed,
            totalValue:   supplied,
            baseRate:     BASE_RATE,
            slope1:       SLOPE1,
            slope2:       SLOPE2,
            optimalRatio: OPTIMAL_RATIO
        });
    }

    /**********************************************************************************************/
    /*** Assertion helper functions                                                             ***/
    /**********************************************************************************************/

    struct AssertPoolReserveStateParams {
        address asset;
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

        DataTypes.ReserveData memory data = pool.getReserveData(params.asset);

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

    struct AssertDebtTokenStateParams {
        address user;
        address debtToken;
        uint256 userBalance;
        uint256 totalSupply;
    }

    function _assertDebtTokenState(AssertDebtTokenStateParams memory params) internal {
        assertEq(IERC20(params.debtToken).balanceOf(params.user), params.userBalance, "userBalance");
        assertEq(IERC20(params.debtToken).totalSupply(),          params.totalSupply, "totalSupply");
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

    function isAddress(bytes32 _bytes) public pure returns (bool) {
        if (_bytes == 0) return false;

        // Extract the 20 bytes Ethereum address
        address extractedAddress;
        assembly {
            extractedAddress := mload(add(_bytes, 0x14))
        }

        // Check if the address equals the original bytes32 value when padded back to bytes32
        return extractedAddress != address(0) && bytes32(bytes20(extractedAddress)) == _bytes;
    }

    function bytes32ToAddress(bytes32 _bytes) public pure returns (address) {
        require(isAddress(_bytes), "bytes32ToAddress/invalid-address");
        return address(uint160(uint256(_bytes)));
    }

}
