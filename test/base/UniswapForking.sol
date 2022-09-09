// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IQuoter} from "v3-periphery/interfaces/IQuoter.sol";
import {ISwapRouter} from "v3-periphery/interfaces/ISwapRouter.sol";
import {INonfungiblePositionManager} from
    "test/mocks/uniswap/INonfungiblePositionManager.sol";

contract UniswapForking {
    INonfungiblePositionManager positionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    IQuoter quoter = IQuoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);
    ISwapRouter router = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
}
