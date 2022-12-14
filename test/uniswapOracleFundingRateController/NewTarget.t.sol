// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.17;

import "./BaseUniswapOracleFundingRateController.t.sol";

contract NewTargetTest is BaseUniswapOracleFundingRateControllerTest {
    function testNewTargetReturnsCurrentTargetIfNoTimeHasPassed() public {
        assertEq(fundingRateController.newTarget(), fundingRateController.target());
    }

    function testNewTargetComputesCorrectlyIfTimeHasPassed() public {
        vm.warp(block.timestamp + 1 weeks);
        assertTrue(fundingRateController.newTarget() != fundingRateController.target());
    }
}
