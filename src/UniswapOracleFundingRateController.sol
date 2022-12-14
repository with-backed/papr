// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeCastLib} from "solmate/utils/SafeCastLib.sol";

import {OracleLibrary} from "src/libraries/OracleLibrary.sol";
import {UniswapHelpers} from "src/libraries/UniswapHelpers.sol";
import {
    IUniswapOracleFundingRateController,
    IFundingRateController
} from "src/interfaces/IUniswapOracleFundingRateController.sol";

contract UniswapOracleFundingRateController is IUniswapOracleFundingRateController {
    /// @inheritdoc IFundingRateController
    ERC20 public immutable underlying;
    /// @inheritdoc IFundingRateController
    ERC20 public immutable papr;
    /// @inheritdoc IFundingRateController
    uint256 public fundingPeriod;
    /// @inheritdoc IUniswapOracleFundingRateController
    address public pool;
    /// @dev the max value of target / mark, used as a guard in _multiplier
    uint256 immutable targetMarkRatioMax;
    /// @dev the min value of target / mark, used as a guard in _multiplier
    uint256 immutable targetMarkRatioMin;
    // single slot, write together
    uint128 internal _target;
    int56 internal _lastCumulativeTick;
    uint48 internal _lastUpdated;
    int24 internal _lastTwapTick;

    constructor(ERC20 _underlying, ERC20 _papr, uint256 _targetMarkRatioMax, uint256 _targetMarkRatioMin) {
        underlying = _underlying;
        papr = _papr;

        targetMarkRatioMax = _targetMarkRatioMax;
        targetMarkRatioMin = _targetMarkRatioMin;

        _setFundingPeriod(4 weeks);
    }

    /// @inheritdoc IFundingRateController
    function updateTarget() public override returns (uint256 nTarget) {
        if (_lastUpdated == block.timestamp) {
            return _target;
        }

        (int56 latestCumulativeTick, int24 latestTwapTick) = _latestTwapTickAndTickCumulative();
        nTarget = _newTarget(latestTwapTick, _target);

        _target = SafeCastLib.safeCastTo128(nTarget);
        // will not overflow for 8000 years
        _lastUpdated = uint48(block.timestamp);
        _lastCumulativeTick = latestCumulativeTick;
        _lastTwapTick = latestTwapTick;

        emit UpdateTarget(nTarget);
    }

    /// @inheritdoc IFundingRateController
    function newTarget() public view override returns (uint256) {
        if (_lastUpdated == block.timestamp) {
            return _target;
        }
        (, int24 latestTwapTick) = _latestTwapTickAndTickCumulative();
        return _newTarget(latestTwapTick, _target);
    }

    /// @inheritdoc IFundingRateController
    function mark() public view returns (uint256) {
        if (_lastUpdated == block.timestamp) {
            return _mark(_lastTwapTick);
        }
        (, int24 latestTwapTick) = _latestTwapTickAndTickCumulative();
        return _mark(latestTwapTick);
    }

    /// @inheritdoc IFundingRateController
    function lastUpdated() external view override returns (uint256) {
        return _lastUpdated;
    }

    /// @inheritdoc IFundingRateController
    function target() external view override returns (uint256) {
        return _target;
    }

    /// @notice initializes the controller, setting pool and target
    /// @dev assumes pool is initialized
    /// @param target the start value of target
    /// @param _pool the pool address to use
    function _init(uint256 target, address _pool) internal {
        if (_lastUpdated != 0) revert AlreadyInitialized();

        _setPool(_pool);

        _lastUpdated = uint48(block.timestamp);
        _target = SafeCastLib.safeCastTo128(target);
        _lastCumulativeTick = OracleLibrary.latestCumulativeTick(pool);

        emit UpdateTarget(target);
    }

    /// @notice Updates `pool`
    /// @dev reverts if new pool does not have same token0 and token1 as `pool`
    /// @dev intended to be used in inherited contract with owner guard
    function _setPool(address _pool) internal {
        if (pool != address(0) && !UniswapHelpers.poolsHaveSameTokens(pool, _pool)) revert PoolTokensDoNotMatch();
        if (!UniswapHelpers.isUniswapPool(_pool)) revert InvalidUniswapV3Pool();

        pool = _pool;

        emit SetPool(_pool);
    }

    /// @notice Updates fundingPeriod
    /// @dev reverts if period is longer than 90 days or less than 7
    function _setFundingPeriod(uint256 _fundingPeriod) internal {
        if (_fundingPeriod < 7 days) revert FundingPeriodTooShort();
        if (_fundingPeriod > 90 days) revert FundingPeriodTooLong();

        fundingPeriod = _fundingPeriod;

        emit SetFundingPeriod(_fundingPeriod);
    }

    /// @dev internal function to allow optimized SLOADs
    function _newTarget(int24 latestTwapTick, uint256 cachedTarget) internal view returns (uint256) {
        return FixedPointMathLib.mulWadDown(cachedTarget, _multiplier(latestTwapTick, cachedTarget));
    }

    /// @dev internal function to allow optimized SLOADs
    function _mark(int24 twapTick) internal view returns (uint256) {
        return OracleLibrary.getQuoteAtTick(twapTick, 1e18, address(papr), address(underlying));
    }

    /// @dev reverts if block.timestamp - _lastUpdated == 0
    function _latestTwapTickAndTickCumulative() internal view returns (int56 tickCumulative, int24 twapTick) {
        tickCumulative = OracleLibrary.latestCumulativeTick(pool);
        twapTick = OracleLibrary.timeWeightedAverageTick(
            _lastCumulativeTick, tickCumulative, int56(uint56(block.timestamp - _lastUpdated))
        );
    }

    /// @notice The multiplier to apply to target() to get newTarget()
    /// @dev Computes the funding rate for the time since _lastUpdates
    /// 1 = 1e18, i.e.
    /// > 1e18 means positive funding rate
    /// < 1e18 means negative funding rate
    /// sub 1e18 to get percent change
    /// @return multiplier used to obtain newTarget()
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
