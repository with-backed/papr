// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {OracleLibrary} from "src/libraries/OracleLibrary.sol";
import {UniswapHelpers} from "src/libraries/UniswapHelpers.sol";

contract FundingRateController {
    event UpdateTarget(uint256 newTarget);
    event SetPool(address indexed pool);

    error PoolTokensDoNotMatch();
    error AlreadyInitialized();

    ERC20 public immutable underlying;
    ERC20 public immutable papr;
    // TODO: method to update for oracle
    uint256 public fundingPeriod = 4 weeks;
    address public pool;
    uint256 immutable targetMarkRatioMax;
    uint256 immutable targetMarkRatioMin;
    // single slot, write together
    uint128 public target;
    int56 lastCumulativeTick;
    uint48 public lastUpdated;
    int24 lastTwapTick;

    constructor(ERC20 _underlying, ERC20 _papr, uint256 _targetMarkRatioMax, uint256 _targetMarkRatioMin) {
        underlying = _underlying;
        papr = _papr;

        targetMarkRatioMax = _targetMarkRatioMax;
        targetMarkRatioMin = _targetMarkRatioMin;
    }

    function updateTarget() public returns (uint256 nTarget) {
        uint128 previousTarget = target;
        if (lastUpdated == block.timestamp) {
            return previousTarget;
        }

        (int56 latestCumulativeTick, int24 latestTwapTick) = _latestTwapTickAndTickCumulative();
        nTarget = _newTarget(latestTwapTick, previousTarget);

        target = uint128(nTarget);
        lastUpdated = uint48(block.timestamp);
        lastCumulativeTick = latestCumulativeTick;
        lastTwapTick = latestTwapTick;

        emit UpdateTarget(nTarget);
    }

    function newTarget() public view returns (uint256) {
        if (lastUpdated == block.timestamp) {
            return target;
        }
        (, int24 latestTwapTick) = _latestTwapTickAndTickCumulative();
        return _newTarget(latestTwapTick, target);
    }

    function mark() public view returns (uint256) {
        if (lastUpdated == block.timestamp) {
            return _mark(lastTwapTick);
        }
        (, int24 latestTwapTick) = _latestTwapTickAndTickCumulative();
        return _mark(latestTwapTick);
    }

    function multiplier() public view returns (uint256) {
        if (lastUpdated == block.timestamp) {
            return _multiplier(lastTwapTick, target);
        }
        (, int24 latestTwapTick) = _latestTwapTickAndTickCumulative();
        return _multiplier(latestTwapTick, target);
    }

    function _init(uint256 _target, uint160 initSqrtRatio) internal {
        if (lastUpdated != 0) revert AlreadyInitialized();

        address _pool = UniswapHelpers.deployAndInitPool(address(underlying), address(papr), 10000, initSqrtRatio);
        _setPool(_pool);

        lastUpdated = uint48(block.timestamp);
        target = uint128(_target);
        lastCumulativeTick = OracleLibrary.latestCumulativeTick(pool);

        emit UpdateTarget(_target);
    }

    function _setPool(address _pool) internal {
        if (pool != address(0) && !UniswapHelpers.poolsHaveSameTokens(pool, _pool)) revert PoolTokensDoNotMatch();
        pool = _pool;

        emit SetPool(_pool);
    }

    function _newTarget(int24 latestTwapTick, uint256 cachedTarget) internal view returns (uint256) {
        return FixedPointMathLib.mulWadDown(target, _multiplier(latestTwapTick, cachedTarget));
    }

    function _mark(int24 twapTick) internal view returns (uint256) {
        return OracleLibrary.getQuoteAtTick(twapTick, 1e18, address(papr), address(underlying));
    }

    /// @dev reverts if block.timestamp - lastUpdated == 0
    function _latestTwapTickAndTickCumulative() internal view returns (int56 tickCumulative, int24 twapTick) {
        tickCumulative = OracleLibrary.latestCumulativeTick(pool);
        twapTick = OracleLibrary.timeWeightedAverageTick(
            lastCumulativeTick, tickCumulative, int56(uint56(block.timestamp - lastUpdated))
        );
    }

    // computing funding rate for the past period
    // > 1e18 means positive funding rate
    // < 1e18 means negative funding rate
    function _multiplier(int24 latestTwapTick, uint256 cachedTarget) internal view returns (uint256) {
        uint256 m = _mark(latestTwapTick);
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
