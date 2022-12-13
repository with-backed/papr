// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./BaseUniswapOracleFundingRateController.t.sol";

contract MultiplierTest is BaseUniswapOracleFundingRateControllerTest {
    function testMultiplierStartsAtOne() public {
        int24 latestTwapTick = fundingRateController.lastTwapTick();
        uint256 target = fundingRateController.target();
        assertEq(fundingRateController.multiplier(latestTwapTick, target), 1e18);
    }

    function testMultiplierDoesNotGoUnderMinBound() public {
        fundingRateController.setFundingPeriod(5 weeks);
        vm.warp(block.timestamp + 5 weeks);

        assertEq(
            fundingRateController.multiplier(fundingRateController.lastTwapTick(), fundingRateController.target()),
            0.8e18 - 1
        );
    }
}
