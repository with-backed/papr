// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseLendingStrategyTest} from "test/core/lendingStrategy/BaseLendingStrategy.ft.sol";
// import {LendingStrategy} from "src/core/LendingStrategy.sol";
// import {ILendingStrategy} from "src/interfaces/ILendingStrategy.sol";
// import {ReservoirOracleUnderwriter} from "src/core/ReservoirOracleUnderwriter.sol";
// import {TestERC721} from "test/mocks/TestERC721.sol";

contract LiquidationPrice is BaseLendingStrategyTest {
    function testReturnsMaxUintIfNoDebt() public {
        uint256 price = strategy.liquidationPrice(borrower);
        assertEq(price, type(uint256).max);
    }
}