// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {TickMath} from "fullrange/libraries/TickMath.sol";

import {BasePaprControllerTest} from "test/paprController/BasePaprController.ft.sol";
import {IPaprController} from "src/interfaces/IPaprController.sol";
import {PaprController} from "src/PaprController.sol";

contract MintAndSellDebt is BasePaprControllerTest {
    function testMintAndSellDebt() public {
        vm.startPrank(borrower);
        nft.approve(address(controller), collateralId);
        controller.addCollateral(collateral);
        PaprController.SwapParams memory swapParams = PaprController.SwapParams({
            amount: debt,
            minOut: 982507,
            sqrtPriceLimitX96: _maxSqrtPriceLimit({sellingPAPR: true}),
            swapFeeTo: address(5),
            swapFeeBips: 100
        });
        uint256 underlyingOut = controller.mintAndSellDebt(
            borrower, collateral.addr, swapParams, oracleInfo
        );
        uint256 fee = underlyingOut * swapParams.swapFeeBips / 1e4;
        assertEq(underlying.balanceOf(swapParams.swapFeeTo), fee);
        assertEq(underlying.balanceOf(borrower), underlyingOut - fee);
        assertEq(debt, controller.vaultInfo(borrower, collateral.addr).debt);
    }
}
