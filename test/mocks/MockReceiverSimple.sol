
// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { IERC20, MockERC20 } from "../SparkLendTestBase.sol";

import { IFlashLoanSimpleReceiver, IPool, IPoolAddressesProvider } from 'sparklend-v1-core/contracts/flashloan/interfaces/IFlashLoanSimpleReceiver.sol';

contract MockReceiverSimpleBase is IFlashLoanSimpleReceiver {

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
        public virtual override returns (bool)
    {}

}

contract MockReceiverSimpleBasic is MockReceiverSimpleBase {

    constructor(address addressesProvider, address pool)
        MockReceiverSimpleBase(addressesProvider, pool) {}

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    )
        public override returns (bool)
    {
        IERC20(asset).approve(address(POOL), amount + premium);

        return true;
    }

}

contract MockReceiverSimpleReturnFalse is MockReceiverSimpleBase {

    constructor(address addressesProvider, address pool)
        MockReceiverSimpleBase(addressesProvider, pool) {}

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    )
        public override returns (bool)
    {
        return false;
    }

}

contract MockReceiverSimpleInsufficientApprove is MockReceiverSimpleBase {

    constructor(address addressesProvider, address pool)
        MockReceiverSimpleBase(addressesProvider, pool) {}

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    )
        public override returns (bool)
    {
        IERC20(asset).approve(address(POOL), amount + premium - 1);

        return true;
    }

}

contract MockReceiverSimpleInsufficientBalance is MockReceiverSimpleBase {

    constructor(address addressesProvider, address pool)
        MockReceiverSimpleBase(addressesProvider, pool) {}

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    )
        public override returns (bool)
    {
        IERC20(asset).approve(address(POOL), amount + premium);
        IERC20(asset).transfer(address(0), 1);

        return true;
    }

}

contract MockReceiverSimpleMintPremium is MockReceiverSimpleBase {

    constructor(address addressesProvider, address pool)
        MockReceiverSimpleBase(addressesProvider, pool) {}

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    )
        public override returns (bool)
    {
        MockERC20(asset).mint(address(this), premium);
        IERC20(asset).approve(address(POOL), amount + premium);

        return true;
    }

}
