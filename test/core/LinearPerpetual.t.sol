// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import "forge-std/Test.sol";

import {LinearPerpetual} from "src/core/LinearPerpetual.sol";

contract LinearPerpetualTest is Test {
    event UpdateNormalization(uint256 newNorm);

    LinearPerpetual lp;

    ERC20 underlying;
    ERC20 perpetual; 
    uint256 targetAPR; 
    uint256 maxLTV;
    uint256 indexMarkRatioMax;
    uint256 indexMarkRatioMin;

    function setUp() public {
        lp = new LinearPerpetual(underlying, perpetual, targetAPR, maxLTV, indexMarkRatioMax, indexMarkRatioMin);
    }

    function updateNormalizationEmitsCorrectly() public {
        vm.warp(block.timestamp + 1);
        /// TODO need to mock a uniswap pool/oracle
    }

}