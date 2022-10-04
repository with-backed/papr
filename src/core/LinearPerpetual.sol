// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {SafeCast} from "v3-core/contracts/libraries/SafeCast.sol";
import {TickMath} from "fullrange/libraries/TickMath.sol";

import {DebtToken} from "./DebtToken.sol";
import {Multicall} from "src/core/base/Multicall.sol";
import {IPostCollateralCallback} from "src/interfaces/IPostCollateralCallback.sol";
import {ILendingStrategy} from "src/interfaces/IPostCollateralCallback.sol";
import {OracleLibrary} from "src/libraries/OracleLibrary.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {BoringOwnable} from "@boringsolidity/BoringOwnable.sol";

contract LinearPerpetual {
    event UpdateNormalization(uint256 newNorm);

    uint256 public immutable start;
    ERC20 public immutable underlying;
    ERC20 public immutable perpetual;
    uint256 public maxLTV;
    uint256 public targetAPR;
    uint256 public PERIOD = 4 weeks;
    uint256 public targetGrowthPerPeriod;
    // for oracle
    IUniswapV3Pool public pool;
    // TODO having these in storage is expensive vs. constants
    // + users might want some guarentees. We should probably lock the max/min or 
    // lock the period. Really only need to pull one lever? 
    uint256 indexMarkRatioMax;
    uint256 indexMarkRatioMin;
    // single slot, write together
    uint128 public normalization;
    uint72 public lastUpdated;
    int56 lastCumulativeTick;

    constructor(ERC20 _underlying, ERC20 _perpetual, uint256 _targetAPR, uint256 _maxLTV, uint256 _indexMarkRatioMax, uint256 _indexMarkRatioMin) {
        underlying = _underlying;
        perpetual = _perpetual;

        targetAPR = _targetAPR;
        maxLTV = _maxLTV;
        targetGrowthPerPeriod = targetAPR / (365 days / PERIOD);

        start = block.timestamp;

        indexMarkRatioMax = _indexMarkRatioMax;
        indexMarkRatioMin = _indexMarkRatioMin;
    }

    function updateNormalization() public {
        if (lastUpdated == block.timestamp) {
            return;
        }
        uint128 previousNormalization = normalization;
        int56 latestCumulativeTick = OracleLibrary.latestCumulativeTick(pool);
        uint256 newNormalization = _newNorm(latestCumulativeTick);

        normalization = uint128(newNormalization);
        lastUpdated = uint72(block.timestamp);
        lastCumulativeTick = latestCumulativeTick;

        emit UpdateNormalization(newNormalization);
    }

    function newNorm() public view returns (uint256) {
        return _newNorm(OracleLibrary.latestCumulativeTick(pool));
    }

    // what each Debt Token is worth in underlying, according to target growth
    function index() public view returns (uint256) {
        return FixedPointMathLib.divWadDown(block.timestamp - start, PERIOD) * targetGrowthPerPeriod
            / FixedPointMathLib.WAD + FixedPointMathLib.WAD;
    }

    function markTwapSinceLastUpdate() public view returns (uint256) {
        return _markTwapSinceLastUpdate(OracleLibrary.latestCumulativeTick(pool));
    }

    /// aka norm growth if updated right now,
    /// e.g. a result of 12e17 = 1.2 = 20% growth since lastUpdate
    function multiplier() public view returns (int256) {
        return _multiplier(OracleLibrary.latestCumulativeTick(pool));
    }

    function _init() internal {
        lastUpdated = uint72(block.timestamp);
        normalization = uint128(FixedPointMathLib.WAD);
        lastCumulativeTick = OracleLibrary.latestCumulativeTick(pool);

        emit UpdateNormalization(FixedPointMathLib.WAD);
    }

    function _newNorm(int56 latestCumulativeTick) internal view returns (uint256) {
        return FixedPointMathLib.mulWadDown(normalization, uint256(_multiplier(latestCumulativeTick)));
    }

    function _markTwapSinceLastUpdate(int56 latestCumulativeTick) internal view returns (uint256) {
        uint256 delta = block.timestamp - lastUpdated;
        if (delta == 0) {
            return OracleLibrary.getQuoteAtTick(
                int24(latestCumulativeTick), 1e18, address(perpetual), address(underlying)
            );
        } else {
            int24 twapTick =
                OracleLibrary.timeWeightedAverageTick(lastCumulativeTick, latestCumulativeTick, int56(uint56(delta)));
            return OracleLibrary.getQuoteAtTick(twapTick, 1e18, address(perpetual), address(underlying));
        }
    }

    function _multiplier(int56 latestCumulativeTick) internal view returns (int256) {
        uint256 m = _markTwapSinceLastUpdate(latestCumulativeTick);
        // TODO: do we need signed ints? when does powWAD return a negative?
        uint256 period = block.timestamp - lastUpdated;
        uint256 periodRatio = FixedPointMathLib.divWadDown(period, PERIOD);
        uint256 targetGrowth = FixedPointMathLib.mulWadDown(targetGrowthPerPeriod, periodRatio) + FixedPointMathLib.WAD;
        uint256 indexMarkRatio;
        if (m == 0) {
            indexMarkRatio = 14e17;
        } else {
            indexMarkRatio = FixedPointMathLib.divWadDown(index(), m);
            // cap at 140%, floor at 80%
            if (indexMarkRatio > indexMarkRatioMax) {
                indexMarkRatio = indexMarkRatioMax;
            } else if (indexMarkRatio < indexMarkRatioMin) {
                indexMarkRatio = indexMarkRatioMin;
            }
        }

        /// accelerate or deccelerate apprecation based in index/mark. If mark is too high, slow down. If mark is too low, speed up.
        int256 deviationMultiplier = FixedPointMathLib.powWad(int256(indexMarkRatio), int256(periodRatio));

        return deviationMultiplier * int256(targetGrowth) / int256(FixedPointMathLib.WAD);
    }
}
