// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./BaseUniswapOracleFundingRateController.t.sol";

contract UpdateTargetTest is BaseUniswapOracleFundingRateControllerTest {
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
    }

    function testUpdateUpdatesTargetToNewTargetValue() public {
        int56[] memory _tickCumulatives = new int56[](1);
        _tickCumulatives[0] = 10;
        MinimalObservablePool(fundingRateController.pool()).setTickComulatives(_tickCumulatives);
        vm.warp(block.timestamp + 1);
        uint256 n = fundingRateController.newTarget();
        uint256 cached = fundingRateController.target();
        assertTrue(n != cached);
        fundingRateController.updateTarget();
        assertEq(n, fundingRateController.target());
    }

    function testUpdateTargetUpdatesLastUpdated() public {
        uint256 newTime = block.timestamp + 10;
        vm.warp(newTime);
        assertTrue(newTime != fundingRateController.lastUpdated());
        fundingRateController.updateTarget();
        assertEq(newTime, fundingRateController.lastUpdated());
    }

    function testUpdatesLastCumulativeTick() public {
        vm.warp(block.timestamp + 1);
        int56[] memory _tickCumulatives = new int56[](1);
        _tickCumulatives[0] = -200;
        MinimalObservablePool(fundingRateController.pool()).setTickComulatives(_tickCumulatives);
        (int56 latest,) = fundingRateController.latestTwapTickAndTickCumulative();
        assertTrue(latest != fundingRateController.lastCumulativeTick());
        fundingRateController.updateTarget();
        assertEq(latest, fundingRateController.lastCumulativeTick());
    }

    function testUpdatesLastTwapTick() public {
        vm.warp(block.timestamp + 1);
        int56[] memory _tickCumulatives = new int56[](1);
        _tickCumulatives[0] = -200;
        MinimalObservablePool(fundingRateController.pool()).setTickComulatives(_tickCumulatives);
        (, int24 latest) = fundingRateController.latestTwapTickAndTickCumulative();
        assertTrue(latest != fundingRateController.lastTwapTick());
        fundingRateController.updateTarget();
        assertEq(latest, fundingRateController.lastTwapTick());
    }

    function testUpdateTargetEmitsNewTarget() public {
        vm.warp(block.timestamp + 1);
        vm.expectEmit(false, false, false, true);
        emit UpdateTarget(fundingRateController.newTarget());
        fundingRateController.updateTarget();
    }

    function testUpdateTargetCalledSameBlockReturnsCurrentTarget() public {
        uint256 cached = fundingRateController.target();
        assertEq(cached, fundingRateController.updateTarget());
    }
}
