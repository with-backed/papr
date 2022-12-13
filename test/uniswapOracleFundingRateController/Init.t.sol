// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./BaseUniswapOracleFundingRateController.t.sol";

contract FundingRateInitTest is BaseUniswapOracleFundingRateControllerTest {
    function testInitSetsValuesCorrectly() public {
        assertEq(fundingRateController.lastUpdated(), uint48(block.timestamp));
        assertEq(fundingRateController.target(), 1e6);
        assertEq(fundingRateController.lastCumulativeTick(), 0);
        assertEq(fundingRateController.lastTwapTick(), 0);
    }
}
