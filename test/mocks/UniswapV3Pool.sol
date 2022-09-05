// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract UniswapV3Pool {
    function token0() public returns (address) {}

    function initialize(uint160 sqrtPriceX96) public {}

    function observe(uint32[] calldata secondsAgo)
        public
        returns (
            int56[] memory tickCumulatives,
            uint160[] memory secondsPerLiquidityCumulativeX128s
        )
    {
        tickCumulatives = new int56[](secondsAgo.length);
        secondsPerLiquidityCumulativeX128s = new uint160[](secondsAgo.length);
        tickCumulatives[0] = 1;
    }
}
