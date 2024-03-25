// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ReserveConfiguration } from "aave-v3-core/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";

import { DataTypes } from "aave-v3-core/contracts/protocol/libraries/types/DataTypes.sol";
import { Errors }    from "aave-v3-core/contracts/protocol/libraries/helpers/Errors.sol";

import { Ethereum } from "sparklend-address-registry/Ethereum.sol";

import { IntegrationTestBase } from "./IntegrationTestBase.sol";

contract StableBorrowTests is IntegrationTestBase {

    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    address borrower = makeAddr("borrower");

    function test_stableBorrowImpossible() public {
        address[] memory reserves = pool.getReservesList();

        _supplyAndUseAsCollateral(borrower, Ethereum.WETH, 1000 ether);

        vm.startPrank(borrower);

        for (uint256 i = 0; i < reserves.length; i++) {
            // Still assert that borrow can't be called
            if (!pool.getReserveData(reserves[i]).configuration.getBorrowingEnabled()) {
                vm.expectRevert();
                pool.borrow(reserves[i], 100, 1, 0, borrower);
                continue;
            }

            vm.expectRevert(bytes(Errors.STABLE_BORROWING_NOT_ENABLED));
            pool.borrow(reserves[i], 100, 1, 0, borrower);
        }
    }

    function test_stableRepayImpossible() public {
        address[] memory reserves = pool.getReservesList();

        _supplyAndUseAsCollateral(borrower, Ethereum.WETH, 1000 ether);

        // Snapshot and revert to avoid issues with siloed borrowing
        uint256 snapshot = vm.snapshot();

        for (uint256 i = 0; i < reserves.length; i++) {
            if (!pool.getReserveData(reserves[i]).configuration.getBorrowingEnabled()) continue;

            _borrow(borrower, reserves[i], 100);

            vm.prank(borrower);
            vm.expectRevert(bytes(Errors.NO_DEBT_OF_SELECTED_TYPE));
            pool.repay(reserves[i], 100, 1, borrower);

            vm.revertTo(snapshot);
        }
    }

    function test_stableSwapBorrowRateModeImpossible() public {
        address[] memory reserves = pool.getReservesList();

        _supplyAndUseAsCollateral(borrower, Ethereum.WETH, 1000 ether);

        // Snapshot and revert to avoid issues with siloed borrowing
        uint256 snapshot = vm.snapshot();

        for (uint256 i = 0; i < reserves.length; i++) {
            if (!pool.getReserveData(reserves[i]).configuration.getBorrowingEnabled()) continue;

            _borrow(borrower, reserves[i], 100);

            vm.prank(borrower);
            vm.expectRevert(bytes(Errors.NO_OUTSTANDING_STABLE_DEBT));
            pool.swapBorrowRateMode(reserves[i], 1);

            vm.revertTo(snapshot);
        }
    }

    function test_rebalanceStableBorrowRateImpossible() public {
        address[] memory reserves = pool.getReservesList();

        _supplyAndUseAsCollateral(borrower, Ethereum.WETH, 1000 ether);

        // Snapshot and revert to avoid issues with siloed borrowing
        uint256 snapshot = vm.snapshot();

        for (uint256 i = 0; i < reserves.length; i++) {
            if (!pool.getReserveData(reserves[i]).configuration.getBorrowingEnabled()) continue;

            _borrow(borrower, reserves[i], 100);

            vm.prank(borrower);
            vm.expectRevert(bytes(Errors.INTEREST_RATE_REBALANCE_CONDITIONS_NOT_MET));
            pool.rebalanceStableBorrowRate(reserves[i], borrower);

            vm.revertTo(snapshot);
        }
    }

}