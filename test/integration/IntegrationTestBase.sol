// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { IPool }             from "aave-v3-core/contracts/interfaces/IPool.sol";
import { IPoolConfigurator } from "aave-v3-core/contracts/interfaces/IPoolConfigurator.sol";

import "sparklend-address-registry/Ethereum.sol";

import { UserActions } from "src/UserActions.sol";

contract IntegrationTestBase is UserActions {

    IPool             constant pool             = IPool(Ethereum.POOL);
    IPoolConfigurator constant poolConfigurator = IPoolConfigurator(Ethereum.POOL_CONFIGURATOR);

    function setUp() public {
        vm.createSelectFork(getChain("mainnet").rpcUrl, 19483900);  // March 21, 2024
    }

    /**********************************************************************************************/
    /*** User helper functions                                                                  ***/
    /**********************************************************************************************/

    function _useAsCollateral(address user, address newCollateralAsset) internal {
        _useAsCollateral(address(pool), user, newCollateralAsset);
    }

    function _borrow(address user, address asset, uint256 amount) internal {
        _borrow(address(pool), user, asset, amount);
    }

    function _supply(address user, address asset, uint256 amount) internal {
        _supply(address(pool), user, asset, amount);
    }

    function _repay(address user, address asset, uint256 amount) internal {
        _repay(address(pool), user, asset, amount);
    }

    function _withdraw(address user, address asset, uint256 amount) internal {
        _withdraw(address(pool), user, asset, amount);
    }

    function _supplyAndUseAsCollateral(address user, address asset, uint256 amount) internal {
        _supplyAndUseAsCollateral(address(pool), user, asset, amount);
    }

    /**********************************************************************************************/
    /*** Debugging utility functions                                                            ***/
    /**********************************************************************************************/

    function _etchLibrary(address deployedLib) internal {
        string memory libName;

        if (deployedLib == Ethereum.BORROWLOGIC) libName = "BorrowLogic";
        else if (deployedLib == Ethereum.BRIDGE_LOGIC) libName = "LiquidationLogic";
        else if (deployedLib == Ethereum.EMODE_LOGIC) libName = "RepaymentLogic";
        else if (deployedLib == Ethereum.SUPPLYLOGIC) libName = "SupplyLogic";
        else if (deployedLib == Ethereum.WITHDRAWALLOGIC) libName = "WithdrawalLogic";
        else revert("Unknown library");
        string memory path = string(abi.encodePacked(libName, ".sol:", libName));
        address debuggingLib = deployCode(path, bytes(""));
        vm.etch(deployedLib, debuggingLib.code);
    }

}

