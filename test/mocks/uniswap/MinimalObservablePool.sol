// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";

contract MinimalObservablePool {
    int56[] tickCumulatives;
    ERC20 public token0;
    ERC20 public token1;

    constructor(ERC20 tokenA, ERC20 tokenB) {
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    // we only ever are calling observe with [0] so reasonably _tickCumulatives should never
    // be > length 1
    function setTickComulatives(int56[] calldata _tickCumulatives) external {
        tickCumulatives = _tickCumulatives;
    }

    function observe(uint32[] calldata secondsAgos) external view returns (int56[] memory, uint160[] memory) {
        int56[] memory _tickCumulatives = new int56[](secondsAgos.length);
        uint160[] memory _secondsPerLiquidityCumulativeX128s = new uint160[](secondsAgos.length);
        for (uint256 i = 0; i < secondsAgos.length; i++) {
            _tickCumulatives[i] = tickCumulatives[i];
            _secondsPerLiquidityCumulativeX128s[i] = 0;
        }

        return (_tickCumulatives, _secondsPerLiquidityCumulativeX128s);
    }
}
