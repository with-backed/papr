// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import "forge-std/Test.sol";

import {FundingRateController} from "src/core/FundingRateController.sol";

contract FundingRateControllerTest is Test {
    event UpdateNormalization(uint256 newNorm);

    FundingRateController fundingRateController;

    ERC20 underlying;
    ERC20 perpetual;
    uint256 indexMarkRatioMax;
    uint256 indexMarkRatioMin;

    function setUp() public {
        fundingRateController =
            new FundingRateController(underlying, perpetual, indexMarkRatioMax, indexMarkRatioMin);
    }

    function updateNormalizationEmitsCorrectly() public {
        vm.warp(block.timestamp + 1);
        /// TODO need to mock a uniswap pool/oracle
    }
}
