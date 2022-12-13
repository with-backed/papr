// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./BaseUniswapOracleFundingRateController.t.sol";

contract FundingRateInitTest is BaseUniswapOracleFundingRateControllerTest {
    function testInitSetsValuesCorrectly() public {
        assertTrue(fundingRateController.lastUpdated() != 0);
        assertTrue(fundingRateController.target() != 0);
    }

    function testInitEmitsUpdateTarget() public {
        vm.expectEmit(false, false, false, true);
        emit UpdateTarget(1e6);
        fundingRateController.init(1e6, 0);
    }
}
