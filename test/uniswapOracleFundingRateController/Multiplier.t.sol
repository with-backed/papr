// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.17;

import "./BaseUniswapOracleFundingRateController.t.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

contract MultiplierTest is BaseUniswapOracleFundingRateControllerTest {
    function testMultiplierDoesNotGoUnderMinBound() public {
        fundingRateController.setFundingPeriod(5 weeks);
        vm.warp(block.timestamp + 5 weeks);
        assertEq(fundingRateController.multiplier(2e6, 1e6), indexMarkRatioMin - 1);
    }

    function testMultiplierDoesNotGoOverMaxBound() public {
        fundingRateController.setFundingPeriod(5 weeks);
        vm.warp(block.timestamp + 5 weeks);
        assertEq(fundingRateController.multiplier(0.3e6, 1e6), indexMarkRatioMax - 2);
    }
}
