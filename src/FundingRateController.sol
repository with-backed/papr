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

    uint256 public immutable start;
    ERC20 public immutable underlying;
    ERC20 public immutable papr;
    // TODO: method to update for oracle
    uint256 public fundingPeriod = 4 weeks;
    address public pool;
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
        if (lastUpdated == block.timestamp) {
            return target;
        }
        return _newTarget(OracleLibrary.latestCumulativeTick(pool), target);
    }

    function markTwapSinceLastUpdate() public view returns (uint256) {
        return _markTwapSinceLastUpdate(OracleLibrary.latestCumulativeTick(pool));
    }

    function _init(uint256 _target, uint160 initSqrtRatio) internal {
        address _pool = UniswapHelpers.deployAndInitPool(address(underlying), address(papr), 10000, initSqrtRatio);
        _setPool(_pool);

        lastUpdated = uint72(block.timestamp);
        target = uint128(_target);
        lastCumulativeTick = OracleLibrary.latestCumulativeTick(pool);

        emit UpdateTarget(_target);
    }

    function _setPool(address _pool) internal {
        if (pool != address(0) && !UniswapHelpers.poolsHaveSameTokens(pool, _pool)) revert PoolTokensDoNotMatch();
        pool = _pool;

        emit SetPool(_pool);
    }

    function _newTarget(int56 latestCumulativeTick, uint256 cachedTarget) internal view returns (uint256) {
        return FixedPointMathLib.mulWadDown(target, _multiplier(latestCumulativeTick, cachedTarget));
    }

    function _markTwapSinceLastUpdate(int56 latestCumulativeTick) internal view returns (uint256) {
        int24 twapTick =
            OracleLibrary.timeWeightedAverageTick(lastCumulativeTick, latestCumulativeTick, int56(uint56(block.timestamp - lastUpdated)));
        return OracleLibrary.getQuoteAtTick(twapTick, 1e18, address(papr), address(underlying));
    }

    // computing funding rate for the past period
    // > 1e18 means positive funding rate
    // < 1e18 means negative funding rate
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
