// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeCastLib} from "solmate/utils/SafeCastLib.sol";

import {OracleLibrary} from "src/libraries/OracleLibrary.sol";
import {UniswapHelpers} from "src/libraries/UniswapHelpers.sol";
import {IFundingRateController} from "src/interfaces/IFundingRateController.sol";

contract FundingRateController is IFundingRateController {
    ERC20 public immutable underlying;
    ERC20 public immutable papr;
    uint256 public fundingPeriod;
    address public pool;
    uint256 immutable targetMarkRatioMax;
    uint256 immutable targetMarkRatioMin;
    // single slot, write together
    uint128 internal _target;
    int56 internal lastCumulativeTick;
    uint48 internal _lastUpdated;
    int24 internal lastTwapTick;

    constructor(ERC20 _underlying, ERC20 _papr, uint256 _targetMarkRatioMax, uint256 _targetMarkRatioMin) {
        underlying = _underlying;
        papr = _papr;

        targetMarkRatioMax = _targetMarkRatioMax;
        targetMarkRatioMin = _targetMarkRatioMin;

        _setFundingPeriod(4 weeks);
    }

    function updateTarget() public returns (uint256 nTarget) {
        if (_lastUpdated == block.timestamp) {
            return _target;
        }

        (int56 latestCumulativeTick, int24 latestTwapTick) = _latestTwapTickAndTickCumulative();
        nTarget = _newTarget(latestTwapTick, _target);

        _target = SafeCastLib.safeCastTo128(nTarget);
        _lastUpdated = uint48(block.timestamp);
        lastCumulativeTick = latestCumulativeTick;
        lastTwapTick = latestTwapTick;

        emit UpdateTarget(nTarget);
    }

    function newTarget() public view returns (uint256) {
        if (_lastUpdated == block.timestamp) {
            return _target;
        }
        (, int24 latestTwapTick) = _latestTwapTickAndTickCumulative();
        return _newTarget(latestTwapTick, _target);
    }

    function mark() public view returns (uint256) {
        if (_lastUpdated == block.timestamp) {
            return _mark(lastTwapTick);
        }
        (, int24 latestTwapTick) = _latestTwapTickAndTickCumulative();
        return _mark(latestTwapTick);
    }

    function lastUpdated() external returns(uint256) {
        return _lastUpdated;
    }

    function target() external returns (uint256) {
        return _target;
    }

    function _init(uint256 target, uint160 initSqrtRatio) internal {
        if (_lastUpdated != 0) revert AlreadyInitialized();

        address _pool = UniswapHelpers.deployAndInitPool(address(underlying), address(papr), 10000, initSqrtRatio);
        _setPool(_pool);

        // will not overflow for 8000 years
        _lastUpdated = uint48(block.timestamp);
        _target = SafeCastLib.safeCastTo128(target);
        lastCumulativeTick = OracleLibrary.latestCumulativeTick(pool);

        emit UpdateTarget(target);
    }

    function _setPool(address _pool) internal {
        if (pool != address(0) && !UniswapHelpers.poolsHaveSameTokens(pool, _pool)) revert PoolTokensDoNotMatch();
        pool = _pool;

        emit SetPool(_pool);
    }

    function _setFundingPeriod(uint256 _fundingPeriod) internal {
        if (_fundingPeriod < 7 days) revert FundingPeriodTooShort();
        if (_fundingPeriod > 90 days) revert FundingPeriodTooLong();

        fundingPeriod = _fundingPeriod;

        emit SetFundingPeriod(_fundingPeriod);
    }

    function _newTarget(int24 latestTwapTick, uint256 cachedTarget) internal view returns (uint256) {
        return FixedPointMathLib.mulWadDown(cachedTarget, _multiplier(latestTwapTick, cachedTarget));
    }

    function _mark(int24 twapTick) internal view returns (uint256) {
        return OracleLibrary.getQuoteAtTick(twapTick, 1e18, address(papr), address(underlying));
    }

    /// @dev reverts if block.timestamp - _lastUpdated == 0
    function _latestTwapTickAndTickCumulative() internal view returns (int56 tickCumulative, int24 twapTick) {
        tickCumulative = OracleLibrary.latestCumulativeTick(pool);
        twapTick = OracleLibrary.timeWeightedAverageTick(
            lastCumulativeTick, tickCumulative, int56(uint56(block.timestamp - _lastUpdated))
        );
    }

    // computing funding rate for the past period
    // > 1e18 means positive funding rate
    // < 1e18 means negative funding rate
    function _multiplier(int24 latestTwapTick, uint256 cachedTarget) internal view returns (uint256) {
        uint256 m = _mark(latestTwapTick);
        uint256 period = block.timestamp - _lastUpdated;
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
