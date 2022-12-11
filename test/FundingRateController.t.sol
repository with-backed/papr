// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import "forge-std/Test.sol";

import {MockFundingRateController} from "test/mocks/MockFundingRateController.sol";
import {MinimalObservablePool} from "test/mocks/uniswap/MinimalObservablePool.sol";
import {TestERC20} from "test/mocks/TestERC20.sol";
import {TickMath} from "fullrange/libraries/TickMath.sol";
import {IFundingRateController} from "src/interfaces/IFundingRateController.sol";

contract FundingRateControllerTest is Test {
    event UpdateTarget(uint256 newTarget);
    event SetPool(address indexed pool);
    event SetFundingPeriod(uint256 fundingPeriod);

    MockFundingRateController fundingRateController;

    ERC20 underlying = new TestERC20();
    ERC20 papr = new TestERC20();
    uint256 indexMarkRatioMax = 1.2e18;
    uint256 indexMarkRatioMin = 0.8e18;

    function setUp() public {
        fundingRateController = new MockFundingRateController(underlying, papr, indexMarkRatioMax, indexMarkRatioMin);
        fundingRateController.init(1e18, 0);
        fundingRateController.setPool(address(new MinimalObservablePool(underlying, papr)));
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

    function testSetFundingPeriodEmitsCorrectly() public {
        vm.expectEmit(false, false, false, true);
        emit SetFundingPeriod(5 weeks);
        fundingRateController.setFundingPeriod(5 weeks);
    }

    function testSetFundingPeriodUpdatesFundindPeriod() public {
        fundingRateController.setFundingPeriod(40 days);
        assertEq(40 days, fundingRateController.fundingPeriod());
    }

    function testSetFundingPeriodRevertsIfPeriodTooShort() public {
        vm.expectRevert(IFundingRateController.FundingPeriodTooShort.selector);
        fundingRateController.setFundingPeriod(5 days);
    }

    function testSetFundingPeriodRevertsIfPeriodTooLong() public {
        vm.expectRevert(IFundingRateController.FundingPeriodTooLong.selector);
        fundingRateController.setFundingPeriod(91 days);
    }

    function testSetPoolRevertsIfWrongToken0() public {
        address token0 = address(1);
        MinimalObservablePool p = new MinimalObservablePool(ERC20(token0), papr);
        vm.expectRevert(IFundingRateController.PoolTokensDoNotMatch.selector);
        fundingRateController.setPool(address(p));
    }

    function testSetPoolRevertsIfWrongToken1() public {
        address token1 = address(type(uint160).max);
        MinimalObservablePool p = new MinimalObservablePool(ERC20(token1), papr);
        vm.expectRevert(IFundingRateController.PoolTokensDoNotMatch.selector);
        fundingRateController.setPool(address(p));
    }

    function testSetPoolUpdatesPoolCorrectly() public {
        MinimalObservablePool p = new MinimalObservablePool(underlying, papr);
        fundingRateController.setPool(address(p));
        assertEq(address(p), fundingRateController.pool());
    }
}
