// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import {TickMath} from "fullrange/libraries/TickMath.sol";
import {FullMath} from "fullrange/libraries/FullMath.sol";


library OracleLibrary {
    /// from https://github.com/Uniswap/v3-periphery/blob/main/contracts/libraries/OracleLibrary.sol#L49
    function getQuoteAtTick(
        int24 tick,
        uint128 baseAmount,
        address baseToken,
        address quoteToken
    ) internal pure returns (uint256 quoteAmount) {
        unchecked {
            uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(tick);

            // Calculate quoteAmount with better precision if it doesn't overflow when multiplied by itself
            if (sqrtRatioX96 <= type(uint128).max) {
                uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
                quoteAmount = baseToken < quoteToken
                    ? FullMath.mulDiv(ratioX192, baseAmount, 1 << 192)
                    : FullMath.mulDiv(1 << 192, baseAmount, ratioX192);
            } else {
                uint256 ratioX128 = FullMath.mulDiv(sqrtRatioX96, sqrtRatioX96, 1 << 64);
                quoteAmount = baseToken < quoteToken
                    ? FullMath.mulDiv(ratioX128, baseAmount, 1 << 128)
                    : FullMath.mulDiv(1 << 128, baseAmount, ratioX128);
            }
        }
    }
}