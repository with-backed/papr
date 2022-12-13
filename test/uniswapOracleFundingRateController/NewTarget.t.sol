// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

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
