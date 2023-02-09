// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.17;

import {IUniswapV3PoolDerivedState} from "v3-core/contracts/interfaces/pool/IUniswapV3PoolDerivedState.sol";
import {IUniswapV3PoolState} from "v3-core/contracts/interfaces/pool/IUniswapV3PoolState.sol";
import {MainnetForking} from "test/base/MainnetForking.sol";
import {UniswapForking} from "test/base/UniswapForking.sol";
import {TickMath} from "fullrange/libraries/TickMath.sol";

import {UniswapOracleFundingRateController} from "src/UniswapOracleFundingRateController.sol";
import "./BaseUniswapOracleFundingRateController.t.sol";
import {UniswapHelpers, IUniswapV3Pool} from "src/libraries/UniswapHelpers.sol";

contract InitableFundingRateController is UniswapOracleFundingRateController {
    constructor(ERC20 _underlying, ERC20 _papr)
        UniswapOracleFundingRateController(_underlying, _papr)
    {}

    function init(uint256 target, address _pool) external {
        _init(target, _pool);
    }

    function lastCumulativeTick() external view returns (int56) {
        return _lastCumulativeTick;
    }

    function lastTwapTick() external view returns (int24) {
        return _lastTwapTick;
    }
}

contract InitTest is MainnetForking, UniswapForking {
    event UpdateTarget(uint256 newTarget);

    ERC20 underlying = new TestERC20();
    ERC20 papr = new TestERC20Papr();

    InitableFundingRateController fundingRateController;

    function setUp() public {
        fundingRateController =
            new InitableFundingRateController(underlying, papr);
    }

    function testConstructorSetsValuesCorrectly() public {
        assertEq(address(fundingRateController.papr()), address(papr));
        assertEq(address(fundingRateController.underlying()), address(underlying));
    }

    function testInitSetsTarget() public {
        uint256 target = 1e18;
        address p = _deployPool();
        fundingRateController.init(target, p);
        assertEq(fundingRateController.target(), target);
    }

    function testEmitsUpdateTarget() public {
        uint256 target = 1e18;
        address p = _deployPool();
        vm.expectEmit(false, false, false, true);
        emit UpdateTarget(target);
        fundingRateController.init(target, p);
    }

    function testInitUpdatesLastUpdated() public {
        address p = _deployPool();
        fundingRateController.init(1e18, p);
        assertEq(fundingRateController.lastUpdated(), block.timestamp);
    }

    function testInitUpdatesLastTwapTick() public {
        address p = _deployPool();
        fundingRateController.init(1e18, p);
        int24 tick = 200;
        vm.mockCall(
            p, abi.encodeWithSelector(IUniswapV3PoolState.slot0.selector), abi.encode(0, 200, 0, 0, 0, 0, false)
        );
        assertEq(fundingRateController.lastTwapTick(), tick);
    }

    function testInitUpdatesLastCumulativeTick() public {
        address p = _deployPool();
        uint32[] memory secondAgos = new uint32[](1);
        secondAgos[0] = 0;
        int56[] memory tickCumulatives = new int56[](1);
        tickCumulatives[0] = 200;
        vm.mockCall(
            p,
            abi.encodeWithSelector(IUniswapV3PoolDerivedState.observe.selector, secondAgos),
            abi.encode(tickCumulatives, tickCumulatives)
        );
        fundingRateController.init(1e18, p);
        assertEq(fundingRateController.lastCumulativeTick(), 200);
    }

    function _deployPool() internal returns (address) {
        return
            UniswapHelpers.deployAndInitPool(address(papr), address(underlying), 3000, TickMath.getSqrtRatioAtTick(200));
    }
}
