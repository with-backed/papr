// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.17;

import {TickMath} from "fullrange/libraries/TickMath.sol";

import {BasePaprControllerTest} from "./BasePaprController.ft.sol";
import {IPaprController} from "../../src/interfaces/IPaprController.sol";
import {PaprController} from "../../src/PaprController.sol";

contract IncreaseDebtAndSellTest is BasePaprControllerTest {
    function testIncreaseDebtAndSell() public {
        vm.startPrank(borrower);
        nft.approve(address(controller), collateralId);
        IPaprController.Collateral[] memory c = new IPaprController.Collateral[](1);
        c[0] = collateral;
        controller.addCollateral(c);
        IPaprController.SwapParams memory swapParams = IPaprController.SwapParams({
            amount: debt,
            minOut: 982507,
            sqrtPriceLimitX96: _maxSqrtPriceLimit({sellingPAPR: true}),
            swapFeeTo: address(5),
            swapFeeBips: 100
        });
        emit log_named_uint('target before swap', controller.newTarget());
        uint256 underlyingOut = controller.increaseDebtAndSell(borrower, collateral.addr, swapParams, oracleInfo);
        uint256 fee = (underlyingOut * swapParams.swapFeeBips) / 1e4;
        assertEq(underlying.balanceOf(swapParams.swapFeeTo), fee);
        assertEq(underlying.balanceOf(borrower), underlyingOut - fee);
        assertEq(debt, controller.vaultInfo(borrower, collateral.addr).debt);
        uint256 t = controller.target();
        emit log_named_uint('target after swap', controller.newTarget());
        vm.warp(block.timestamp + 60);
        emit log_named_uint('target 60 seconds swap', controller.newTarget());
        vm.warp(block.timestamp + 10 minutes);
        emit log_named_uint('target 10 minutes swap', controller.newTarget());
        emit log_named_uint('APR (divide by 1e4 to get %)', (controller.newTarget() - t) * 1e18 / 10 minutes * 365 days / 1e18);
        vm.warp(block.timestamp + 1 days);
        emit log_named_uint('target 1 day after swap', controller.newTarget());
        emit log_named_uint('APR (divide by 1e4 to get %)', (controller.newTarget() - t) * 1e18 / 1 days * 365 days / 1e18);
        vm.warp(block.timestamp + 7 days);
        emit log_named_uint('target 7 days after swap', controller.newTarget());
        emit log_named_uint('APR (divide by 1e4 to get %)', (controller.newTarget() - t) * 1e18 / 8 days * 365 days / 1e18);
    }
}
