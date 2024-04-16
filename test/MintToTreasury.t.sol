// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { IERC20 } from "erc20-helpers/interfaces/IERC20.sol";

import { SparkLendTestBase } from "./SparkLendTestBase.sol";

contract MintToTreasuryTests is SparkLendTestBase {

    function setUp() public override {
        super.setUp();
        
        vm.prank(admin);
        poolConfigurator.setReserveFactor(address(borrowAsset), 5_00);
    }

    function test_mintToTreasury_01() public proveNoOp {
        address[] memory assets = new address[](1);
        assets[0] = makeAddr("invalid-asset");

        vm.startStateDiffRecording();
        pool.mintToTreasury(assets);
    }

    function test_mintToTreasury_02() public proveNoOp {
        vm.prank(admin);
        poolConfigurator.setReserveActive(address(borrowAsset), false);
        
        address[] memory assets = new address[](1);
        assets[0] = address(borrowAsset);

        vm.startStateDiffRecording();
        pool.mintToTreasury(assets);
    }

    function test_mintToTreasury_03() public proveNoOp {        
        address[] memory assets = new address[](1);
        assets[0] = address(borrowAsset);

        vm.startStateDiffRecording();
        pool.mintToTreasury(assets);
    }

    function test_mintToTreasury_04() public proveNoOp {
        address borrower = makeAddr("borrower");

        _initCollateral({
            asset:                address(collateralAsset),
            ltv:                  50_00,
            liquidationThreshold: 50_00,
            liquidationBonus:     100_01
        });

        vm.prank(admin);
        poolConfigurator.setReserveBorrowing(address(borrowAsset), true);

        _supplyAndUseAsCollateral(borrower, address(collateralAsset), 1000 ether);
        _supply(borrower, address(borrowAsset), 1 ether);
        _borrow(borrower, address(borrowAsset), 1 ether);

        skip(100 days);

        address[] memory assets = new address[](1);
        assets[0] = address(borrowAsset);

        assertEq(pool.getReserveData(address(borrowAsset)).accruedToTreasury, 0);

        vm.startStateDiffRecording();
        pool.mintToTreasury(assets);
    }

    function test_mintToTreasury_05() public {
        address borrower = makeAddr("borrower");

        _initCollateral({
            asset:                address(collateralAsset),
            ltv:                  50_00,
            liquidationThreshold: 50_00,
            liquidationBonus:     100_01
        });

        vm.prank(admin);
        poolConfigurator.setReserveBorrowing(address(borrowAsset), true);

        _supplyAndUseAsCollateral(borrower, address(collateralAsset), 1000 ether);
        _supply(borrower, address(borrowAsset), 500 ether);
        _borrow(borrower, address(borrowAsset), 100 ether);  // 20% utilization = 5 + (20%/80%) * 2% = 5.5%

        skip(WARP_TIME);

        // borrowRate * utilization * (1 - reserveFactor)
        uint256 liquidityRate = 0.055e27 * 20/100 * 95/100;
        uint256 supplierYield = 500 ether * liquidityRate / 100 / 1e27;  // 1% of a year has passed

        assertEq(pool.getReserveData(address(borrowAsset)).currentLiquidityRate, liquidityRate);
        assertEq(pool.getReserveData(address(borrowAsset)).accruedToTreasury,    0);

        // Update reserve state without updating reserve value
        _supply(borrower, address(borrowAsset), 1 ether);  
        _withdraw(borrower, address(borrowAsset), 1 ether);

        // assertEq(pool.getReserveData(address(borrowAsset)).accruedToTreasury, 2);

        uint256 liquidityIndex = 1e27 + (1e27 * liquidityRate / 100 / 1e27);

        uint256 compoundedNormalizedInterest = _getCompoundedNormalizedInterest(0.055e27, WARP_TIME);

        // NOTE: This is only true on the first index update
        uint256 borrowIndex = compoundedNormalizedInterest;

        assertEq(pool.getReserveData(address(borrowAsset)).variableBorrowIndex, borrowIndex);

        uint256 borrowerInterest = (compoundedNormalizedInterest - 1e27) * 100 ether / 1e27;

        assertEq(borrowerInterest, 0.055015127565607543 ether);

        uint256 scaledAccruedToTreasury = borrowerInterest * 5/100 * 1e27 / liquidityIndex;
        
        assertEq(pool.getReserveData(address(borrowAsset)).accruedToTreasury, scaledAccruedToTreasury); 

        // IERC20 debtToken = IERC20(pool.getReserveData(address(borrowAsset)).variableDebtTokenAddress);

        // assertEq(debtToken.totalSupply(), 100 ether + borrowerInterest); 

        assertEq(aBorrowAsset.totalSupply(), 500 ether + supplierYield);

        address[] memory assets = new address[](1);
        assets[0] = address(borrowAsset);
        pool.mintToTreasury(assets);

        assertEq(aBorrowAsset.totalSupply(), 500 ether + supplierYield + scaledAccruedToTreasury * liquidityIndex / 1e27 + 1);

        // assertEq(pool.getReserveData(address(borrowAsset)).accruedToTreasury, 0); 

        // assertEq(debtToken.totalSupply(), 100 ether + borrowerInterest + scaledAccruedToTreasury * liquidityIndex / 1e27); 
    }

}
