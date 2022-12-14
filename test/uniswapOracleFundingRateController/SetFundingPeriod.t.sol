// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.13;

import "./BaseUniswapOracleFundingRateController.t.sol";

contract SetFundingPeriodTest is BaseUniswapOracleFundingRateControllerTest {
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
}
