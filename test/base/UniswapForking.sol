// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.17;

import {IQuoter} from "v3-periphery/interfaces/IQuoter.sol";
import {ISwapRouter} from "v3-periphery/interfaces/ISwapRouter.sol";
import {INonfungiblePositionManager} from "../mocks/uniswap/INonfungiblePositionManager.sol";
import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";

contract UniswapForking {
    INonfungiblePositionManager positionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    IQuoter quoter = IQuoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);
    ISwapRouter router = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    IUniswapV3Factory factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
}
