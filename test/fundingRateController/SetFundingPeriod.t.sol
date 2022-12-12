// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./BaseFundingRateController.t.sol";

contract SetFundingPeriodTest is BaseFundingRateControllerTest {
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