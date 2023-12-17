// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.13;

contract MockOracle {

    int256 _price;

    function __setPrice(int256 price) public {
        _price = price;
    }

    function latestAnswer() external view returns (int256) {
        return _price;
    }

}
