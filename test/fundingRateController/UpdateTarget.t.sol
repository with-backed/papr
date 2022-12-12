// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./BaseFundingRateController.t.sol";

contract UpdateTargetTest is BaseFundingRateControllerTest {
    function testFuzzUpdateTarget(int56 newTickCumulative, uint32 secondsPassed) public {
        vm.warp(block.timestamp + secondsPassed);
        vm.assume(secondsPassed != 0);
        // at very high values, we will see reverts due int overflows on oldTarget * multiplier
        // we think it is reasonable to assume the contract will be touched once every ten years, or
        // is otherwise defunct
        vm.assume(secondsPassed < 365 days * 10);
        /// last cumulative tick is 0, set in setup
        /// each seconds tickCumulative can change by no more than max tick and no less than min
        vm.assume((newTickCumulative / int256(int32(secondsPassed))) < TickMath.MAX_TICK);
        vm.assume((newTickCumulative / int256(int32(secondsPassed))) > TickMath.MIN_TICK);
        int56[] memory _tickCumulatives = new int56[](1);
        _tickCumulatives[0] = newTickCumulative;
        MinimalObservablePool(fundingRateController.pool()).setTickComulatives(_tickCumulatives);
        fundingRateController.updateTarget();
        fundingRateController.newTarget();
    }
}
