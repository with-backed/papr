// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {TickMath} from "fullrange/libraries/TickMath.sol";

import {BasePaprControllerTest} from "test/paprController/BasePaprController.ft.sol";
import {IPaprController} from "src/interfaces/IPaprController.sol";
import {PaprController} from "src/PaprController.sol";
import {UniswapHelpers} from "src/libraries/UniswapHelpers.sol";

contract BuyAndReduceDebt is BasePaprControllerTest {
    function testBuyAndReduceDebtReducesDebt() public {
        vm.startPrank(borrower);
        nft.approve(address(controller), collateralId);
        IPaprController.Collateral[] memory c = new IPaprController.Collateral[](1);
        c[0] = collateral;
        controller.addCollateral(c);
        IPaprController.SwapParams memory swapParams = IPaprController.SwapParams({
            amount: debt,
            minOut: 982507,
            sqrtPriceLimitX96: _maxSqrtPriceLimit({sellingPAPR: true}),
            swapFeeTo: address(0),
            swapFeeBips: 0
        });
        uint256 underlyingOut = controller.increaseDebtAndSell(borrower, collateral.addr, swapParams, oracleInfo);
        IPaprController.VaultInfo memory vaultInfo = controller.vaultInfo(borrower, collateral.addr);
        assertEq(vaultInfo.debt, debt);
        assertEq(underlyingOut, underlying.balanceOf(borrower));
        uint256 fee;
        underlying.approve(address(controller), underlyingOut + underlyingOut * fee / 1e4);
        swapParams = IPaprController.SwapParams({
            amount: underlyingOut,
            minOut: 1,
            sqrtPriceLimitX96: _maxSqrtPriceLimit({sellingPAPR: false}),
            swapFeeTo: address(5),
            swapFeeBips: fee
        });
        uint256 debtPaid = controller.buyAndReduceDebt(borrower, collateral.addr, swapParams);
        assertGt(debtPaid, 0);
        vaultInfo = controller.vaultInfo(borrower, collateral.addr);
        assertEq(vaultInfo.debt, debt - debtPaid);
        assertEq(underlying.balanceOf(swapParams.swapFeeTo), fee);
    }

    function testBuyAndReduceDebtRevertsIfMinOutTooLittle() public {
        vm.startPrank(borrower);
        nft.approve(address(controller), collateralId);
        IPaprController.Collateral[] memory c = new IPaprController.Collateral[](1);
        c[0] = collateral;
        controller.addCollateral(c);
        IPaprController.SwapParams memory swapParams = IPaprController.SwapParams({
            amount: debt,
            minOut: 982507,
            sqrtPriceLimitX96: _maxSqrtPriceLimit({sellingPAPR: true}),
            swapFeeTo: address(0),
            swapFeeBips: 0
        });
        uint256 underlyingOut = controller.increaseDebtAndSell(borrower, collateral.addr, swapParams, oracleInfo);
        underlying.approve(address(controller), underlyingOut);
        uint160 priceLimit = _maxSqrtPriceLimit({sellingPAPR: false});
        uint256 out = quoter.quoteExactInputSingle({
            tokenIn: address(underlying),
            tokenOut: address(controller.papr()),
            fee: 10000,
            amountIn: underlyingOut,
            sqrtPriceLimitX96: priceLimit
        });
        vm.expectRevert(abi.encodeWithSelector(UniswapHelpers.TooLittleOut.selector, out, out + 1));
        swapParams = IPaprController.SwapParams({
            amount: underlyingOut,
            minOut: out + 1,
            sqrtPriceLimitX96: priceLimit,
            swapFeeTo: address(0),
            swapFeeBips: 0
        });
        uint256 debtPaid = controller.buyAndReduceDebt(borrower, collateral.addr, swapParams);
    }
}
