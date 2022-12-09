// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import "forge-std/Test.sol";

import {MockFundingRateController} from "test/mocks/MockFundingRateController.sol";
import {MinimalObservablePool} from "test/mocks/uniswap/MinimalObservablePool.sol";
import {TestERC20} from "test/mocks/TestERC20.sol";

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

    function testUpdateTarget(int56[2] calldata tickCumulatives) public {
        int56[] memory _tickCumulatives = new int56[](tickCumulatives.length);
        for (uint i = 0; i < tickCumulatives.length; i++) {
            // vm.assume(tickCumulatives[i] != 0);
            // if (i > 0) vm.assume(tickCumulatives[i] != tickCumulatives[i - 1]);
            _tickCumulatives[i] = tickCumulatives[i];
        }
        MinimalObservablePool(fundingRateController.pool()).setTickComulatives(_tickCumulatives);
        // fundingRateController.setTickComulatives(tick);
        fundingRateController.updateTarget();
        fundingRateController.newTarget();

    }

    // function updateTargetEmitsCorrectly() public {
    //     vm.warp(block.timestamp + 1);
    //     /// TODO need to mock a uniswap pool/oracle
    // }
}
