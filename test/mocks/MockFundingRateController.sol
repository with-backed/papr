// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {ERC20} from "solmate/tokens/ERC20.sol";

import {UniswapOracleFundingRateController} from "src/UniswapOracleFundingRateController.sol";

contract MockFundingRateController is UniswapOracleFundingRateController {
    constructor(ERC20 _underlying, ERC20 _papr, uint256 _targetMarkRatioMax, uint256 _targetMarkRatioMin)
        UniswapOracleFundingRateController(_underlying, _papr, _targetMarkRatioMax, _targetMarkRatioMin)
    {}

    function setPool(address _pool) external {
        _setPool(_pool);
    }

    function setPoolCheat(address _pool) external {
        pool = _pool;
    }

    function setFundingPeriod(uint256 _fundingPeriod) external {
        _setFundingPeriod(_fundingPeriod);
    }

    function setLastCumulativeTick(int56 tick) external {
        _lastCumulativeTick = tick;
    }

    function setLastTwapTick(int24 tick) external {
        _lastTwapTick = tick;
    }

    function init(uint256 target, int56 initCumulativeTick) external {
        _lastUpdated = uint48(block.timestamp);
        _target = uint128(target);
        _lastCumulativeTick = initCumulativeTick;
        _lastTwapTick = int24(initCumulativeTick);
    }

    function latestTwapTickAndTickCumulative() external view returns (int56 tickCumulative, int24 twapTick) {
        return _latestTwapTickAndTickCumulative();
    }

    function lastCumulativeTick() external view returns (int56) {
        return _lastCumulativeTick;
    }

    function lastTwapTick() external view returns (int24) {
        return _lastTwapTick;
    }

    function multiplier(uint256 mark, uint256 target) external returns (uint256) {
        return _multiplier(mark, target);
    }
}
