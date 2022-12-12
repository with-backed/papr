// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";

import {FundingRateController} from "src/FundingRateController.sol";

contract MockFundingRateController is FundingRateController {
    constructor(ERC20 _underlying, ERC20 _papr, uint256 _targetMarkRatioMax, uint256 _targetMarkRatioMin)
        FundingRateController(_underlying, _papr, _targetMarkRatioMax, _targetMarkRatioMin)
    {}

    function setPool(address _pool) external {
        _setPool(_pool);
    }

    function setFundingPeriod(uint256 _fundingPeriod) external {
        _setFundingPeriod(_fundingPeriod);
    }

    function setLastCumulativeTick(int56 tick) external {
        lastCumulativeTick = tick;
    }

    function setLastTwapTick(int24 tick) external {
        lastTwapTick = tick;
    }

    function init(uint256 _target, int56 initCumulativeTick) external {
        _lastUpdated = uint48(block.timestamp);
        _target = uint128(_target);
        lastCumulativeTick = initCumulativeTick;
        lastTwapTick = int24(initCumulativeTick);
    }
}
