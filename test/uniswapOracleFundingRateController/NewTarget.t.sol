// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./BaseUniswapOracleFundingRateController.t.sol";

contract NewTargetTest is BaseUniswapOracleFundingRateControllerTest {
    function testNewTargetReturnsCurrentTargetIfNoTimeHasPassed() public {
        assertEq(fundingRateController.newTarget(), 1e6);
    }

    function testNewTargetComputesCorrectlyIfTimeHasPassed() public {
        vm.warp(block.timestamp + 1 weeks);
        uint256 newTarget = fundingRateController.newTarget();
        assertEq(newTarget, 945741);
    }
}
