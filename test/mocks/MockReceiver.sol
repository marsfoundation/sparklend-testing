// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { IERC20, MockERC20 } from "test/SparkLendTestBase.sol";

import { IFlashLoanReceiver, IPool, IPoolAddressesProvider } from 'sparklend-v1-core/contracts/flashloan/interfaces/IFlashLoanReceiver.sol';

contract MockReceiverBase is IFlashLoanReceiver {

    IPoolAddressesProvider public immutable ADDRESSES_PROVIDER;
    IPool                  public immutable POOL;

    constructor(address addressesProvider, address pool) {
        POOL               = IPool(pool);
        ADDRESSES_PROVIDER = IPoolAddressesProvider(addressesProvider);
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    )
        external virtual returns (bool)
    {}

}

contract MockReceiverBasic is MockReceiverBase {

    constructor(address addressesProvider, address pool)
        MockReceiverBase(addressesProvider, pool) {}

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    )
        public override returns (bool)
    {
        for (uint256 i = 0; i < assets.length; i++) {
            IERC20(assets[i]).approve(address(POOL), amounts[i] + premiums[i]);
        }
        return true;
    }

}

contract MockReceiverReturnFalse is MockReceiverBase {

    constructor(address addressesProvider, address pool)
        MockReceiverBase(addressesProvider, pool) {}

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    )
        public override returns (bool)
    {
        return false;
    }

}

contract MockReceiverInsufficientApprove is MockReceiverBase {

    address addressToRevertOn;

    constructor(address addressesProvider, address pool, address addressToRevertOn_)
        MockReceiverBase(addressesProvider, pool)
    {
        addressToRevertOn = addressToRevertOn_;
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    )
        public override returns (bool)
    {
        for (uint256 i = 0; i < assets.length; i++) {
            uint256 amount = amounts[i] + premiums[i];
            if (assets[i] == addressToRevertOn) {
                amount -= 1;
            }
            IERC20(assets[i]).approve(address(POOL), amount);
        }
        return true;
    }

}

contract MockReceiverInsufficientBalance is MockReceiverBase {

    address addressToRevertOn;

    constructor(address addressesProvider, address pool, address addressToRevertOn_)
        MockReceiverBase(addressesProvider, pool)
    {
        addressToRevertOn = addressToRevertOn_;
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    )
        public override returns (bool)
    {
        for (uint256 i = 0; i < assets.length; i++) {
            if (assets[i] == addressToRevertOn) {
                IERC20(assets[i]).transfer(address(0), 1);
            }
            IERC20(assets[i]).approve(address(POOL), amounts[i] + premiums[i]);
        }
        return true;
    }

}

contract MockReceiverMintPremium is MockReceiverBase {

    constructor(address addressesProvider, address pool)
        MockReceiverBase(addressesProvider, pool) {}

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    )
        public override returns (bool)
    {
        for (uint256 i = 0; i < assets.length; i++) {
            MockERC20(assets[i]).mint(address(this), premiums[i]);
            IERC20(assets[i]).approve(address(POOL), amounts[i] + premiums[i]);
        }
        return true;
    }

}
