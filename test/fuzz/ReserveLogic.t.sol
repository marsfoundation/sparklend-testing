// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { SparkLendTestBase } from "test/SparkLendTestBase.sol";

import { ReserveLogicWrapper } from "test/fuzz/wrappers/ReserveLogicWrapper.sol";

contract ReserveLogicTests is SparkLendTestBase {

    uint256 constant TOKEN_MAX = 1e40;  // 1e22 at 1e18 precision

    ReserveLogicWrapper wrapper;

    function setUp() public override {
        super.setUp();

        _supply(makeAddr("borrower"), address(borrowAsset), 100 ether);

        address wrapperDeployment = address(new ReserveLogicWrapper(poolAddressesProvider));

        vm.etch(address(pool), wrapperDeployment.code);

        // Get wrapper interface at pool address after etching
        wrapper = ReserveLogicWrapper(address(pool));
    }

    function test_cumulateToLiquidityIndex_basicExample() external {
        assertEq(_getLiquidityIndex(), 1e27);

        uint256 prevIndex     = _getLiquidityIndex();
        uint256 returnedIndex = wrapper.cumulateToLiquidityIndex(address(borrowAsset), 1000, 1);
        uint256 newIndex      = _getLiquidityIndex();

        assertEq(returnedIndex, newIndex);
        assertEq(returnedIndex, prevIndex * (1e27 + (1 * 1e27 / 1000)) / 1e27);
    }

    function testFuzz_cumulateToLiquidityIndex_firstExample(
        uint256 totalLiquidity1,
        uint256 totalLiquidity2,
        uint256 amount1,
        uint256 amount2
    )
        external
    {
        totalLiquidity1 = bound(totalLiquidity1, 1, TOKEN_MAX);
        totalLiquidity2 = bound(totalLiquidity2, 1, TOKEN_MAX);
        amount1         = bound(amount1,         1, totalLiquidity1);
        amount2         = bound(amount2,         1, totalLiquidity2);

        uint256 index0 = _getLiquidityIndex();

        assertEq(index0, 1e27);

        // First cumulation - max rounding up is 1

        uint256 returnedIndex1 = wrapper.cumulateToLiquidityIndex(address(borrowAsset), totalLiquidity1, amount1);
        uint256 index1         = _getLiquidityIndex();

        assertEq(index1, returnedIndex1);
        assertEq(index1, _rayMul(index0, 1e27 + _rayDiv(amount1, totalLiquidity1)));

        assertApproxEqAbs(index1, index0 * (1e27 + (amount1 * 1e27 / totalLiquidity1)) / 1e27, 1);

        // Second cumulation - max rounding up is 3

        uint256 returnedIndex2 = wrapper.cumulateToLiquidityIndex(address(borrowAsset), totalLiquidity2, amount2);
        uint256 index2         = _getLiquidityIndex();

        assertEq(index2, returnedIndex2);
        assertEq(index2, _rayMul(index1, 1e27 + _rayDiv(amount2, totalLiquidity2)));

        assertApproxEqAbs(index2, index1 * (1e27 + (amount2 * 1e27 / totalLiquidity2)) / 1e27, 3);
    }

    function testFuzz_cumulateToLiquidityIndex_growingRoundingDifference(
        uint256 totalLiquidity,
        uint256 amount
    )
        external
    {
        for (uint256 i; i < 100; ++i) {
            totalLiquidity = _bound(_random(totalLiquidity, i), 1, 1e27);
            amount         = _bound(_random(totalLiquidity, i), 1, totalLiquidity / 10);  // Max of 10% growth

            wrapper.cumulateToLiquidityIndex(address(borrowAsset), totalLiquidity, amount);

            uint256 prevIndex     = _getLiquidityIndex();
            uint256 returnedIndex = wrapper.cumulateToLiquidityIndex(address(borrowAsset), totalLiquidity, amount);
            uint256 newIndex      = _getLiquidityIndex();

            assertEq(newIndex, returnedIndex);
            assertEq(newIndex, _rayMul(prevIndex, 1e27 + _rayDiv(amount, totalLiquidity)));

            // As prevIndex scales in magnitude, its product deviates in rounding, scaling with its size, plus one from rayMul
            assertApproxEqAbs(
                newIndex,
                prevIndex * (1e27 + (amount * 1e27 / totalLiquidity)) / 1e27,
                2 + prevIndex / 1e27
            );
        }
    }

    /**********************************************************************************************/
    /*** Helper functions                                                                       ***/
    /**********************************************************************************************/

    function _getLiquidityIndex() internal view returns (uint256) {
        return wrapper.getReserveData(address(borrowAsset)).liquidityIndex;
    }

    function _random(uint256 startingValue, uint256 salt) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(startingValue, salt)));
    }

    function _rayMul(uint256 a, uint256 b) internal pure returns (uint256) {
        return ((a * b) + 0.5e27) / 1e27;  // Round up half
    }

    function _rayDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        return ((a * 1e27) + (b / 2)) / b;  // Round up half
    }
}
