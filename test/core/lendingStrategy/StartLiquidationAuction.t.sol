// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseLendingStrategyTest} from "test/core/lendingStrategy/BaseLendingStrategy.ft.sol";
import {ILendingStrategy} from "src/interfaces/ILendingStrategy.sol";

contract StartLiquidationAuctionTest is BaseLendingStrategyTest {
    function testRevertsIfNotLiquidatable() public {
        _openLoan();
        vm.expectRevert(ILendingStrategy.NotLiquidatable.selector);
        strategy.startLiquidationAuction(borrower, ILendingStrategy.Collateral({id: collateralId, addr: nft}));
    }

    function testRevertsIfInvalidCollateralAccountPair() public {
        _openLoan();
        _makeLiquidatable();
        vm.expectRevert(ILendingStrategy.InvalidCollateralAccountPair.selector);
        strategy.startLiquidationAuction(address(0xded), ILendingStrategy.Collateral({id: collateralId, addr: nft}));
    }

    function testRevertsIfAuctionOngoing() public {
        _openLoan();
        _makeLiquidatable();
        strategy.startLiquidationAuction(borrower, ILendingStrategy.Collateral({id: collateralId, addr: nft}));

        nft.mint(borrower, collateralId + 1);
        vm.startPrank(borrower);
        nft.approve(address(strategy), collateralId + 1);
        strategy.addCollateral(ILendingStrategy.Collateral(nft, collateralId + 1), oracleInfo);

        vm.expectRevert(ILendingStrategy.MinAuctionSpacing.selector);
        strategy.startLiquidationAuction(borrower, ILendingStrategy.Collateral({id: collateralId + 1, addr: nft}));
    }

    function testAllowsNewAuctionIfMinSpacingHasPassed() public {
        _openLoan();
        _makeLiquidatable();
        strategy.startLiquidationAuction(borrower, ILendingStrategy.Collateral({id: collateralId, addr: nft}));

        nft.mint(borrower, collateralId + 1);
        vm.startPrank(borrower);
        nft.approve(address(strategy), collateralId + 1);
        strategy.addCollateral(ILendingStrategy.Collateral(nft, collateralId + 1), oracleInfo);

        vm.warp(block.timestamp + strategy.liquidationAuctionMinSpacing());
        strategy.startLiquidationAuction(borrower, ILendingStrategy.Collateral({id: collateralId + 1, addr: nft}));
    }

    // test removes collateral value from vault
    // removes frozen collateral value
    // test updates latest ongoing auction

    function _openLoan() internal {
        safeTransferReceivedArgs.debt = strategy.maxDebt(oraclePrice) - 2;
        safeTransferReceivedArgs.minOut = 1;
        safeTransferReceivedArgs.sqrtPriceLimitX96 = _maxSqrtPriceLimit(true);
        vm.prank(borrower);
        nft.safeTransferFrom(borrower, address(strategy), collateralId, abi.encode(safeTransferReceivedArgs));
    }

    function _makeLiquidatable() internal {
        vm.warp(block.timestamp + 1 days);
    }
}