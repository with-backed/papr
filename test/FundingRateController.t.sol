// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import "forge-std/Test.sol";

import {FundingRateController} from "src/FundingRateController.sol";

contract FundingRateControllerTest is Test {
    event UpdateTarget(uint256 newNorm);

    FundingRateController fundingRateController;

    ERC20 underlying;
    ERC20 papr;
    uint256 indexMarkRatioMax;
    uint256 indexMarkRatioMin;

    function setUp() public {
        fundingRateController = new FundingRateController(underlying, papr, indexMarkRatioMax, indexMarkRatioMin);
    }

    function updateTargetEmitsCorrectly() public {
        vm.warp(block.timestamp + 1);
        /// TODO need to mock a uniswap pool/oracle
    }
}
