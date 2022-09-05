// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IUniswapV3Factory} from
    "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {UniswapV3Pool} from "./UniswapV3Pool.sol";

contract UniswapV3Factory is IUniswapV3Factory {
    function owner() external view returns (address) {}

    function feeAmountTickSpacing(uint24 fee) external view returns (int24) {}

    function getPool(address tokenA, address tokenB, uint24 fee)
        external
        view
        returns (address pool)
    {
        (address token0, address token1) =
            tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    function createPool(address tokenA, address tokenB, uint24 fee)
        external
        returns (address pool)
    {
        pool = address(new UniswapV3Pool());
    }

    function setOwner(address _owner) external {}

    function enableFeeAmount(uint24 fee, int24 tickSpacing) external {}
}
