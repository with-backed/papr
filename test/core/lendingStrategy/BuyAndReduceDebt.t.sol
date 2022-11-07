// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {TickMath} from "fullrange/libraries/TickMath.sol";

import {BaseLendingStrategyTest} from "test/core/lendingStrategy/BaseLendingStrategy.ft.sol";
import {ILendingStrategy} from "src/interfaces/ILendingStrategy.sol";
import {LendingStrategy} from "src/core/LendingStrategy.sol";

contract BuyAndReduceDebt is BaseLendingStrategyTest {
    function testBuyAndReduceDebtReducesDebt() public {
        vm.startPrank(borrower);
        nft.approve(address(strategy), collateralId);
        strategy.addCollateral(ILendingStrategy.Collateral(nft, collateralId));
        uint256 underlyingOut = strategy.mintAndSellDebt(
            collateral.addr, debt, 1e16, _maxSqrtPriceLimit({sellingPAPR: true}), borrower, oracleInfo
        );
        ILendingStrategy.VaultInfo memory vaultInfo = strategy.vaultInfo(borrower, collateral.addr);
        assertEq(vaultInfo.debt, debt);
        assertEq(underlyingOut, underlying.balanceOf(borrower));
        underlying.approve(address(strategy), underlyingOut);
        uint256 debtPaid = strategy.buyAndReduceDebt(
            borrower, collateral.addr, underlyingOut, 1, _maxSqrtPriceLimit({sellingPAPR: false}), borrower, oracleInfo
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
            collateral.addr, debt, 1e16, _maxSqrtPriceLimit({sellingPAPR: true}), borrower, oracleInfo
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
        vm.expectRevert(abi.encodeWithSelector(ILendingStrategy.TooLittleOut.selector, out, out + 1));
        uint256 debtPaid = strategy.buyAndReduceDebt(
            borrower, collateral.addr, underlyingOut, out + 1, priceLimit, address(borrower), oracleInfo
        );
    }
}
