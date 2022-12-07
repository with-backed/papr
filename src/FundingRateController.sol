// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {OracleLibrary} from "src/libraries/OracleLibrary.sol";

contract FundingRateController {
    event UpdateTarget(uint256 newTarget);

    uint256 public immutable start;
    ERC20 public immutable underlying;
    ERC20 public immutable papr;
    // TODO: method to update for oracle
    uint256 public fundingPeriod = 4 weeks;
    // TODO: method to update for oracle
    IUniswapV3Pool public pool;
    uint256 immutable targetMarkRatioMax;
    uint256 immutable targetMarkRatioMin;
    // single slot, write together
    uint128 public target;
    uint72 public lastUpdated;
    int56 lastCumulativeTick;

    constructor(ERC20 _underlying, ERC20 _papr, uint256 _targetMarkRatioMax, uint256 _targetMarkRatioMin) {
        underlying = _underlying;
        papr = _papr;

        start = block.timestamp;

        targetMarkRatioMax = _targetMarkRatioMax;
        targetMarkRatioMin = _targetMarkRatioMin;
    }

    function updateTarget() public returns (uint256 nTarget) {
        uint128 previousTarget = target;
        if (lastUpdated == block.timestamp) {
            return previousTarget;
        }

        int56 latestCumulativeTick = OracleLibrary.latestCumulativeTick(pool);
        nTarget = _newTarget(latestCumulativeTick, previousTarget);

        target = uint128(nTarget);
        lastUpdated = uint72(block.timestamp);
        lastCumulativeTick = latestCumulativeTick;

        emit UpdateTarget(nTarget);
    }

    function newTarget() public view returns (uint256) {
        return _newTarget(OracleLibrary.latestCumulativeTick(pool), target);
    }

    function markTwapSinceLastUpdate() public view returns (uint256) {
        return _markTwapSinceLastUpdate(OracleLibrary.latestCumulativeTick(pool));
    }

    function multiplier() public view returns (uint256) {
        return _multiplier(OracleLibrary.latestCumulativeTick(pool), target);
    }

    function _init(uint256 _target) internal {
        lastUpdated = uint72(block.timestamp);
        target = uint128(_target);
        lastCumulativeTick = OracleLibrary.latestCumulativeTick(pool);

        emit UpdateTarget(_target);
    }

    function _newTarget(int56 latestCumulativeTick, uint256 cachedTarget) internal view returns (uint256) {
        return FixedPointMathLib.mulWadDown(target, _multiplier(latestCumulativeTick, cachedTarget));
    }

    function _markTwapSinceLastUpdate(int56 latestCumulativeTick) internal view returns (uint256) {
        uint256 delta = block.timestamp - lastUpdated;
        if (delta == 0) {
            return OracleLibrary.getQuoteAtTick(int24(latestCumulativeTick), 1e18, address(papr), address(underlying));
        } else {
            int24 twapTick =
                OracleLibrary.timeWeightedAverageTick(lastCumulativeTick, latestCumulativeTick, int56(uint56(delta)));
            return OracleLibrary.getQuoteAtTick(twapTick, 1e18, address(papr), address(underlying));
        }
    }

    // computing funding rate for the past period
    function _multiplier(int56 latestCumulativeTick, uint256 cachedTarget) internal view returns (uint256) {
        uint256 m = _markTwapSinceLastUpdate(latestCumulativeTick);
        uint256 period = block.timestamp - lastUpdated;
        uint256 periodRatio = FixedPointMathLib.divWadDown(period, fundingPeriod);
        uint256 targetMarkRatio;
        if (m == 0) {
            targetMarkRatio = targetMarkRatioMax;
        } else {
            targetMarkRatio = FixedPointMathLib.divWadDown(cachedTarget, m);
            if (targetMarkRatio > targetMarkRatioMax) {
                targetMarkRatio = targetMarkRatioMax;
            } else if (targetMarkRatio < targetMarkRatioMin) {
                targetMarkRatio = targetMarkRatioMin;
            }
        }

        // safe to cast because targetMarkRatio > 0
        return uint256(FixedPointMathLib.powWad(int256(targetMarkRatio), int256(periodRatio)));
    }
}
