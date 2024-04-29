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
            selectors: new bytes4[](1)
        });

        fuzzSelector.selectors[0] = lenderHandler.supply.selector;

        targetContract(address(lenderHandler));
        targetSelector(fuzzSelector);
    }

    function invariant_A() public {
        assertGe(aBorrowAsset.totalSupply(), 0);
        console.log("handlerLogs: ", lenderHandler.data("supply"));
    }

}
