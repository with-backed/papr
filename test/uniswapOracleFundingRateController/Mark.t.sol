// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.13;

import {TickMath} from "fullrange/libraries/TickMath.sol";
import "./BaseUniswapOracleFundingRateController.t.sol";

contract MarkTest is BaseUniswapOracleFundingRateControllerTest {
    function testReturnsQuoteFromLastTwapTickIfNoTimePassed() public {
        int24 tick = TickMath.getTickAtSqrtRatio(uint160((1e18 << 96) / 1e18)) / 2;
        fundingRateController.setLastTwapTick(tick);
        assertEq(fundingRateController.mark(), 1e18);
    }

    function testDoesNotReturnQuoteFromLastTwapTickIfNoTimePassed() public {
        int24 tick = TickMath.getTickAtSqrtRatio(uint160((1e18 << 96) / 1e18)) / 2;
        fundingRateController.setLastTwapTick(tick);
        vm.warp(block.timestamp + 1);
        assertTrue(fundingRateController.mark() != 1e18);
    }
}
