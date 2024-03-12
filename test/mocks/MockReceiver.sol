
// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { IERC20, MockERC20 } from "../SparkLendTestBase.sol";

import { IFlashLoanSimpleReceiver, IPool, IPoolAddressesProvider } from 'aave-v3-core/contracts/flashloan/interfaces/IFlashLoanSimpleReceiver.sol';

contract MockReceiverBase is IFlashLoanSimpleReceiver {

    IPoolAddressesProvider public immutable ADDRESSES_PROVIDER;
    IPool                  public immutable POOL;

    constructor(address addressesProvider, address pool) {
        POOL               = IPool(pool);
        ADDRESSES_PROVIDER = IPoolAddressesProvider(addressesProvider);
    }

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    )
        external virtual override returns (bool)
    {}

}

contract MockReceiverBasic is MockReceiverBase {

    constructor(address addressesProvider, address pool)
        MockReceiverBase(addressesProvider, pool) {}

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    )
        external override returns (bool)
    {
        IERC20(asset).approve(address(POOL), amount + premium);

        return true;
    }

}

contract MockReceiverReturnFalse is MockReceiverBase {

    constructor(address addressesProvider, address pool)
        MockReceiverBase(addressesProvider, pool) {}

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    )
        external override returns (bool)
    {
        IERC20(asset).approve(address(POOL), amount + premium);

        return false;
    }

}

contract MockReceiverInsufficientApprove is MockReceiverBase {

    constructor(address addressesProvider, address pool)
        MockReceiverBase(addressesProvider, pool) {}

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    )
        external override returns (bool)
    {
        IERC20(asset).approve(address(POOL), amount + premium - 1);

        return true;
    }

}

contract MockReceiverInsufficientBalance is MockReceiverBase {

    constructor(address addressesProvider, address pool)
        MockReceiverBase(addressesProvider, pool) {}

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    )
        external override returns (bool)
    {
        IERC20(asset).approve(address(POOL), amount + premium);
        IERC20(asset).transfer(address(0), 1);

        return true;
    }

}

contract MockReceiverMintPremium is MockReceiverBase {

    constructor(address addressesProvider, address pool)
        MockReceiverBase(addressesProvider, pool) {}

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    )
        external override returns (bool)
    {
        console.log("amount ", amount);
        console.log("premium", premium);
        MockERC20(asset).mint(address(this), premium);
        IERC20(asset).approve(address(POOL), amount + premium);

        return true;
    }

}
