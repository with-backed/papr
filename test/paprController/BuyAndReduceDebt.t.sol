// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {TickMath} from "fullrange/libraries/TickMath.sol";

import {BasePaprControllerTest} from "test/paprController/BasePaprController.ft.sol";
import {IPaprController} from "src/interfaces/IPaprController.sol";
import {PaprController} from "src/PaprController.sol";

contract BuyAndReduceDebt is BasePaprControllerTest {
    function testBuyAndReduceDebtReducesDebt() public {
        vm.startPrank(borrower);
        nft.approve(address(controller), collateralId);
        controller.addCollateral(IPaprController.Collateral(nft, collateralId));
        PaprController.SwapParams memory swapParams = PaprController.SwapParams({
            amount: debt,
            minOut: 982507,
            sqrtPriceLimitX96: _maxSqrtPriceLimit({sellingPAPR: true}),
            swapFeeTo: address(0),
            swapFeeBips: 0
        });
        uint256 underlyingOut = controller.mintAndSellDebt(
            borrower, collateral.addr, swapParams, oracleInfo
        );
        IPaprController.VaultInfo memory vaultInfo = controller.vaultInfo(borrower, collateral.addr);
        assertEq(vaultInfo.debt, debt);
        assertEq(underlyingOut, underlying.balanceOf(borrower));
        underlying.approve(address(controller), underlyingOut);
        swapParams = PaprController.SwapParams({
            amount: underlyingOut,
            minOut: 1,
            sqrtPriceLimitX96: _maxSqrtPriceLimit({sellingPAPR: false}),
            swapFeeTo: address(0),
            swapFeeBips: 0
        });
        uint256 debtPaid = controller.buyAndReduceDebt(
            borrower, collateral.addr, swapParams
        );
        assertGt(debtPaid, 0);
        vaultInfo = controller.vaultInfo(borrower, collateral.addr);
        assertEq(vaultInfo.debt, debt - debtPaid);
    }

    function testBuyAndReduceDebtRevertsIfMinOutTooLittle() public {
        vm.startPrank(borrower);
        nft.approve(address(controller), collateralId);
        controller.addCollateral(collateral);
        PaprController.SwapParams memory swapParams = PaprController.SwapParams({
            amount: debt,
            minOut: 982507,
            sqrtPriceLimitX96: _maxSqrtPriceLimit({sellingPAPR: true}),
            swapFeeTo: address(0),
            swapFeeBips: 0
        });
        uint256 underlyingOut = controller.mintAndSellDebt(
            borrower, collateral.addr, swapParams, oracleInfo
        );
        underlying.approve(address(controller), underlyingOut);
        uint160 priceLimit = _maxSqrtPriceLimit({sellingPAPR: false});
        uint256 out = quoter.quoteExactInputSingle({
            tokenIn: address(underlying),
            tokenOut: address(controller.papr()),
            fee: 10000,
            amountIn: underlyingOut,
            sqrtPriceLimitX96: priceLimit
        });
        vm.expectRevert(abi.encodeWithSelector(IPaprController.TooLittleOut.selector, out, out + 1));
        swapParams = PaprController.SwapParams({
            amount: underlyingOut,
            minOut: out + 1,
            sqrtPriceLimitX96: priceLimit,
            swapFeeTo: address(0),
            swapFeeBips: 0
        });
        uint256 debtPaid = controller.buyAndReduceDebt(
            borrower, collateral.addr, swapParams
        );
    }
}
