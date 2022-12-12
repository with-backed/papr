// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./BaseUniswapOracleFundingRateController.t.sol";

contract SetPoolTest is BaseUniswapOracleFundingRateControllerTest {
    function testSetPoolRevertsIfWrongToken0() public {
        address token0 = address(1);
        MinimalObservablePool p = new MinimalObservablePool(ERC20(token0), papr);
        vm.expectRevert(IUniswapOracleFundingRateController.PoolTokensDoNotMatch.selector);
        fundingRateController.setPool(address(p));
    }

    function testSetPoolRevertsIfWrongToken1() public {
        address token1 = address(type(uint160).max);
        MinimalObservablePool p = new MinimalObservablePool(ERC20(token1), papr);
        vm.expectRevert(IUniswapOracleFundingRateController.PoolTokensDoNotMatch.selector);
        fundingRateController.setPool(address(p));
    }

    function testSetPoolUpdatesPool() public {
        MinimalObservablePool p = new MinimalObservablePool(underlying, papr);
        fundingRateController.setPool(address(p));
        assertEq(address(p), fundingRateController.pool());
    }

    function testSetPoolEmitsSetPool() public {
        MinimalObservablePool p = new MinimalObservablePool(underlying, papr);
        vm.expectEmit(true, false, false, false);
        emit SetPool(address(p));
        fundingRateController.setPool(address(p));
    }
}
