// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {TickMath} from "fullrange/libraries/TickMath.sol";

import {BasePaprControllerTest} from "test/paprController/BasePaprController.ft.sol";
import {IPaprController} from "src/interfaces/IPaprController.sol";
import {PaprController} from "src/PaprController.sol";

contract BuyAndReduceDebt is BasePaprControllerTest {
    function testBuyAndReduceDebtReducesDebt() public {
        vm.startPrank(borrower);
        nft.approve(address(strategy), collateralId);
        strategy.addCollateral(IPaprController.Collateral(nft, collateralId));
        uint256 underlyingOut = strategy.mintAndSellDebt(
            collateral.addr, debt, 982507, _maxSqrtPriceLimit({sellingPAPR: true}), borrower, oracleInfo
        );
        IPaprController.VaultInfo memory vaultInfo = strategy.vaultInfo(borrower, collateral.addr);
        assertEq(vaultInfo.debt, debt);
        assertEq(underlyingOut, underlying.balanceOf(borrower));
        underlying.approve(address(strategy), underlyingOut);
        uint256 debtPaid = strategy.buyAndReduceDebt(
            borrower, collateral.addr, underlyingOut, 1, _maxSqrtPriceLimit({sellingPAPR: false}), borrower
        );
        assertGt(debtPaid, 0);
        vaultInfo = strategy.vaultInfo(borrower, collateral.addr);
        assertEq(vaultInfo.debt, debt - debtPaid);
    }

    function testBuyAndReduceDebtRevertsIfMinOutTooLittle() public {
        vm.startPrank(borrower);
        nft.approve(address(strategy), collateralId);
        strategy.addCollateral(collateral);
        uint256 underlyingOut = strategy.mintAndSellDebt(
            collateral.addr, debt, 982507, _maxSqrtPriceLimit({sellingPAPR: true}), borrower, oracleInfo
        );
        underlying.approve(address(strategy), underlyingOut);
        uint160 priceLimit = _maxSqrtPriceLimit({sellingPAPR: false});
        uint256 out = quoter.quoteExactInputSingle({
            tokenIn: address(underlying),
            tokenOut: address(strategy.perpetual()),
            fee: 10000,
            amountIn: underlyingOut,
            sqrtPriceLimitX96: priceLimit
        });
        vm.expectRevert(abi.encodeWithSelector(IPaprController.TooLittleOut.selector, out, out + 1));
        uint256 debtPaid =
            strategy.buyAndReduceDebt(borrower, collateral.addr, underlyingOut, out + 1, priceLimit, address(borrower));
    }
}
