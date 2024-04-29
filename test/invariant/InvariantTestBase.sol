// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { SparkLendTestBase } from "test/SparkLendTestBase.sol";

import { LenderHandler } from "test/invariant/handlers/LenderHandler.sol";

contract InvariantTestBase is SparkLendTestBase {

    uint256 constant NUM_LENDERS = 10;

    LenderHandler lenderHandler;

    function setUp() public override {
        super.setUp();

        lenderHandler = new LenderHandler(address(pool), NUM_LENDERS);

        FuzzSelector memory fuzzSelector = FuzzSelector({
            addr: address(lenderHandler),
            selectors: new bytes4[](3)
        });

        fuzzSelector.selectors[0] = lenderHandler.supply.selector;
        fuzzSelector.selectors[1] = lenderHandler.supplyAndUseAsCollateral.selector;
        fuzzSelector.selectors[2] = lenderHandler.withdraw.selector;

        targetContract(address(lenderHandler));
        targetSelector(fuzzSelector);

        _initCollateral({
            asset:                address(borrowAsset),
            ltv:                  50_00,
            liquidationThreshold: 50_00,
            liquidationBonus:     101_00
        });

        _initCollateral({
            asset:                address(collateralAsset),
            ltv:                  50_00,
            liquidationThreshold: 50_00,
            liquidationBonus:     101_00
        });

        vm.startPrank(admin);
        poolConfigurator.setReserveBorrowing(address(borrowAsset),     true);
        poolConfigurator.setReserveBorrowing(address(collateralAsset), true);
        vm.stopPrank();
    }

    function invariant_A() public {
        assertGe(aBorrowAsset.totalSupply(), 0);
        console.log("LenderHandler supply:                   ", lenderHandler.data("supply"));
        console.log("LenderHandler supplyAndUseAsCollateral: ", lenderHandler.data("supplyAndUseAsCollateral"));
        console.log("LenderHandler withdraw:                 ", lenderHandler.data("withdraw"));
        console.log("LenderHandler withdraw - early exit:    ", lenderHandler.data("withdraw - early exit"));
    }

}
