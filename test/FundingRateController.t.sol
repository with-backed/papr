// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import "forge-std/Test.sol";

import {MockFundingRateController} from "test/mocks/MockFundingRateController.sol";
import {MinimalObservablePool} from "test/mocks/uniswap/MinimalObservablePool.sol";
import {TestERC20} from "test/mocks/TestERC20.sol";
import {TickMath} from "fullrange/libraries/TickMath.sol";

contract FundingRateControllerTest is Test {
    // event UpdateTarget(uint256 newNorm);

    MockFundingRateController fundingRateController;

    ERC20 underlying = new TestERC20();
    ERC20 papr = new TestERC20();
    uint256 indexMarkRatioMax = 1.2e18;
    uint256 indexMarkRatioMin = 0.8e18;

    function setUp() public {
        fundingRateController = new MockFundingRateController(underlying, papr, indexMarkRatioMax, indexMarkRatioMin);
        fundingRateController.init(1e18, 0);
        fundingRateController.setPool(address(new MinimalObservablePool()));
    }

    function testFuzzUpdateTarget(int56 newTickCumulative, uint24 secondsPassed) public {
        // breaks if it has been more than > uint24.max (half a year) since updateTarget last called
        vm.warp(block.timestamp + secondsPassed);
        vm.assume(secondsPassed != 0);
        /// last cumulative tick is 0, set in setup
        /// each seconds tickCumulative can change by no more than max tick and no less than min
        vm.assume((newTickCumulative / int256(int24(secondsPassed))) < TickMath.MAX_TICK);
        vm.assume((newTickCumulative / int256(int24(secondsPassed))) > TickMath.MIN_TICK);
        int56[] memory _tickCumulatives = new int56[](1);
        _tickCumulatives[0] = newTickCumulative;
        MinimalObservablePool(fundingRateController.pool()).setTickComulatives(_tickCumulatives);
        fundingRateController.updateTarget();
        fundingRateController.newTarget();
    }
}
