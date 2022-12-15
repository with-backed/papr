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
        uint256 underlyingOut = controller.increaseDebtAndSell(borrower, collateral.addr, swapParams, oracleInfo);
        uint256 fee = (underlyingOut * swapParams.swapFeeBips) / 1e4;
        assertEq(underlying.balanceOf(swapParams.swapFeeTo), fee);
        assertEq(underlying.balanceOf(borrower), underlyingOut - fee);
        assertEq(debt, controller.vaultInfo(borrower, collateral.addr).debt);
    }
}
