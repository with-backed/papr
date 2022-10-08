// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {TickMath} from "fullrange/libraries/TickMath.sol";

import {BaseLendingStrategyTest} from "test/core/lendingStrategy/BaseLendingStrategy.ft.sol";
import {ILendingStrategy} from "src/interfaces/ILendingStrategy.sol";
import {LendingStrategy} from "src/core/LendingStrategy.sol";

contract BuyAndReduceDebt is BaseLendingStrategyTest {
    function testBuyAndReduceDebtReducesDebt() public {
        vm.startPrank(borrower);
        vaultId = strategy.vaultIdentifier(vaultNonce, borrower);
        nft.approve(address(strategy), collateralId);
        strategy.addCollateral(vaultNonce, ILendingStrategy.Collateral(nft, collateralId), oracleInfo);
        uint256 underlyingOut =
            strategy.mintAndSellDebt(vaultNonce, debt, 1e16, _maxSqrtPriceLimit({sellingPAPR: true}), borrower);
        (uint256 vaultDebt,) = strategy.vaultInfo(vaultId);
        assertEq(vaultDebt, debt);
        assertEq(underlyingOut, underlying.balanceOf(borrower));
        underlying.approve(address(strategy), underlyingOut);
        uint256 debtPaid =
            strategy.buyAndReduceDebt(vaultId, underlyingOut, 1, _maxSqrtPriceLimit({sellingPAPR: false}), borrower);
        assertGt(debtPaid, 0);
        (vaultDebt,) = strategy.vaultInfo(vaultId);
        assertEq(vaultDebt, debt - debtPaid);
    }

    function testBuyAndReduceDebtRevertsIfMinOutTooLittle() public {
        vm.startPrank(borrower);
        vaultId = strategy.vaultIdentifier(vaultNonce, borrower);
        nft.approve(address(strategy), collateralId);
        strategy.addCollateral(vaultNonce, ILendingStrategy.Collateral(nft, collateralId), oracleInfo);
        uint256 underlyingOut =
            strategy.mintAndSellDebt(vaultNonce, debt, 1e16, _maxSqrtPriceLimit({sellingPAPR: true}), borrower);
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
        uint256 debtPaid = strategy.buyAndReduceDebt(vaultId, underlyingOut, out + 1, priceLimit, address(borrower));
    }
}
