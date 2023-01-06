// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.17;

import "./BaseUniswapOracleFundingRateController.t.sol";
import {MainnetForking} from "test/base/MainnetForking.sol";
import {UniswapForking} from "test/base/UniswapForking.sol";

contract SetPoolTest is BaseUniswapOracleFundingRateControllerTest, MainnetForking, UniswapForking {
    function testSetPoolRevertsIfWrongToken0() public {
        address token0 = address(1);
        address p = factory.createPool(token0, address(papr), 3000);
        vm.expectRevert(IUniswapOracleFundingRateController.PoolTokensDoNotMatch.selector);
        fundingRateController.setPool(address(p));
    }

    function testSetPoolRevertsIfWrongToken1() public {
        address token1 = address(type(uint160).max);
        address p = factory.createPool(token1, address(papr), 3000);
        vm.expectRevert(IUniswapOracleFundingRateController.PoolTokensDoNotMatch.selector);
        fundingRateController.setPool(address(p));
    }

    function testSetPoolUpdatesPool() public {
        address p = factory.createPool(address(underlying), address(papr), 3000);
        fundingRateController.setPool(p);
        assertEq(p, fundingRateController.pool());
    }

    function testSetPoolEmitsSetPool() public {
        address p = factory.createPool(address(underlying), address(papr), 3000);
        vm.expectEmit(true, false, false, false);
        emit SetPool(address(p));
        fundingRateController.setPool(address(p));
    }

    function testRevertsIfIsNotUniswapV3Pool() public {
        MinimalObservablePool p = new MinimalObservablePool(underlying, papr);
        vm.expectRevert(IUniswapOracleFundingRateController.InvalidUniswapV3Pool.selector);
        fundingRateController.setPool(address(p));
    }
}
