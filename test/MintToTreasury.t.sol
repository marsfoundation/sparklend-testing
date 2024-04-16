// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { IERC20 } from "erc20-helpers/interfaces/IERC20.sol";

import { SparkLendTestBase } from "./SparkLendTestBase.sol";

contract MintToTreasuryTests is SparkLendTestBase {

    address borrower = makeAddr("borrower");

    function setUp() public override {
        super.setUp();
        
        vm.prank(admin);
        poolConfigurator.setReserveFactor(address(borrowAsset), 5_00);
    }

    modifier whenReserveHasAccruedValue {
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
        _borrow(borrower, address(borrowAsset), 100 ether);

        skip(WARP_TIME);

        _;
    }

    modifier whenAccruedToTreasuryHasBeenUpdated {
        // Update reserve state without updating reserve value
        _supply(borrower, address(borrowAsset), 1 ether);  
        _withdraw(borrower, address(borrowAsset), 1 ether);

        _;
    }

    modifier whenMoreTimeHasPassed {
        skip(WARP_TIME);

        _;
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

    function test_mintToTreasury_04() 
        public 
        whenReserveHasAccruedValue
        proveNoOp 
    {
        address[] memory assets = new address[](1);
        assets[0] = address(borrowAsset);

        assertEq(pool.getReserveData(address(borrowAsset)).accruedToTreasury, 0);

        vm.startStateDiffRecording();
        pool.mintToTreasury(assets);
    }

    function test_mintToTreasury_05() 
        public 
        whenReserveHasAccruedValue
        whenAccruedToTreasuryHasBeenUpdated
    {
        // borrowRate * utilization * (1 - reserveFactor)
        uint256 liquidityRate = 0.055e27 * 20/100 * 95/100;
        uint256 supplierYield = 500 ether * liquidityRate / 100 / 1e27;  // 1% of a year has passed

        uint256 liquidityIndex   = 1e27 + (liquidityRate * 1e27 / 100 / 1e27);
        uint256 borrowerInterest = _getBorrowerInterest(0.055e27, WARP_TIME, 100 ether);

        uint256 scaledAccruedToTreasury = borrowerInterest * 5/100 * 1e27 / liquidityIndex;

        assertEq(supplierYield,           0.05225 ether);
        assertEq(borrowerInterest,        0.055015127565607543 ether);  // 5.5% compounded
        assertEq(scaledAccruedToTreasury, 0.002750468954274655 ether);  // 5% of borrowerInterest
        
        assertEq(aBorrowAsset.totalSupply(),             500 ether + supplierYield);
        assertEq(aBorrowAsset.balanceOf(treasury),       0);
        assertEq(aBorrowAsset.scaledBalanceOf(treasury), 0);

        assertEq(pool.getReserveData(address(borrowAsset)).accruedToTreasury, scaledAccruedToTreasury);

        address[] memory assets = new address[](1);
        assets[0] = address(borrowAsset);
        pool.mintToTreasury(assets);
        
        uint256 accruedToTreasury = scaledAccruedToTreasury * liquidityIndex / 1e27 + 1;  // Rounding

        assertEq(accruedToTreasury, 0.002750756378280377 ether);

        assertEq(aBorrowAsset.totalSupply(),             500 ether + supplierYield + accruedToTreasury);
        assertEq(aBorrowAsset.balanceOf(treasury),       accruedToTreasury);
        assertEq(aBorrowAsset.scaledBalanceOf(treasury), scaledAccruedToTreasury);

        assertEq(pool.getReserveData(address(borrowAsset)).accruedToTreasury, 0);
    }

    function test_mintToTreasury_06() 
        public 
        whenReserveHasAccruedValue
        whenAccruedToTreasuryHasBeenUpdated
        whenMoreTimeHasPassed
    {
        // These values were updated at last supply/withdraw which was at WARP_TIME
        // borrowRate * utilization * (1 - reserveFactor)
        uint256 liquidityRate1  = 0.055e27 * 20/100 * 95/100;
        uint256 liquidityIndex1 = 1e27 + (liquidityRate1 * 1e27 / 100 / 1e27);  // 1% of a year has passed

        uint256 borrowerInterest1 = _getBorrowerInterest(0.055e27, WARP_TIME, 100 ether);

        ( uint256 borrowRate2, uint256 liquidityRate2 ) 
            = _getUpdatedRates(100 ether + borrowerInterest1, 500 ether + borrowerInterest1, 5_00);

        uint256 borrowerInterest2 
            = _getBorrowerInterest(borrowRate2, WARP_TIME, 100 ether + borrowerInterest1);

        uint256 liquidityIndex2 = (1e27 + (liquidityRate2 * 1e27 / 100 / 1e27)) * liquidityIndex1 / 1e27;  // 1% of a year has passed
        uint256 supplierYield   = 500 ether * liquidityIndex2 / 1e27 - 500 ether;

        assertEq(pool.getReserveData(address(borrowAsset)).liquidityIndex,       liquidityIndex1);
        assertEq(pool.getReserveNormalizedIncome(address(borrowAsset)),          liquidityIndex2);
        assertEq(pool.getReserveData(address(borrowAsset)).currentLiquidityRate, liquidityRate2);

        // uint256 scaledAccruedToTreasury = borrowerInterest1 * 5/100 * 1e27 / liquidityIndex1;

        // // Rates increase because of the accrued interest increasing utilization
        // assertEq(liquidityRate1,    0.01045e27);
        // assertEq(liquidityRate2,    0.010455017011611857160935024e27);
        // assertEq(liquidityIndex1,   1.0001045e27);
        // assertEq(liquidityIndex2,   1.000209050170116118571609350e27);
        // assertEq(borrowerInterest1, 0.055015127565607543 ether);
        // assertEq(borrowerInterest2, 0.055047596992634301 ether);
        // assertEq(borrowRate2,       0.055002200362996122457081216e27);
        // assertEq(supplierYield,     0.104525085058059285 ether);

        // assertEq(scaledAccruedToTreasury, 0.002750468954274655 ether);
        
        // assertEq(aBorrowAsset.totalSupply(),             500 ether + supplierYield);
        // assertEq(aBorrowAsset.balanceOf(treasury),       0);
        // assertEq(aBorrowAsset.scaledBalanceOf(treasury), 0);

        // assertEq(pool.getReserveData(address(borrowAsset)).accruedToTreasury, scaledAccruedToTreasury);

        // address[] memory assets = new address[](1);
        // assets[0] = address(borrowAsset);
        // pool.mintToTreasury(assets);
        
        // uint256 accruedToTreasury = scaledAccruedToTreasury * liquidityIndex1 / 1e27 + 1;  // Rounding

        // assertEq(accruedToTreasury, 1);

        // // Total supply is higher than the last test, but the treasury balance is the same
        // // Treasury balance only increases when `updateState` is called on pool interactions
        // assertEq(aBorrowAsset.totalSupply(),             500 ether + supplierYield + accruedToTreasury);
        // assertEq(aBorrowAsset.balanceOf(treasury),       accruedToTreasury);
        // assertEq(aBorrowAsset.scaledBalanceOf(treasury), scaledAccruedToTreasury);

        // assertEq(pool.getReserveData(address(borrowAsset)).accruedToTreasury, 0);
    }

    // Try to think of weird edge cases where indexes haven't been updated before minting
    // Update index/accrued, warp, mint, update index, check accrued

}
