// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {INFTEDA} from "NFTEDA/extensions/NFTEDAStarterIncentive.sol";

import {BaseLendingStrategyTest} from "test/core/lendingStrategy/BaseLendingStrategy.ft.sol";
import {ILendingStrategy} from "src/interfaces/ILendingStrategy.sol";

contract PurchaseLiquidationAuctionNFT is BaseLendingStrategyTest {
    INFTEDA.Auction auction;
    address purchaser = address(2);

    function setUp() public override {
        super.setUp();
        _openMaxLoanAndSwap();
        _makeMaxLoanLiquidatable();
        auction = strategy.startLiquidationAuction(borrower, collateral);
        nft.mint(purchaser, collateralId + 1);
        nft.mint(purchaser, collateralId + 2);
        nft.mint(purchaser, collateralId + 3);
        safeTransferReceivedArgs.debt = strategy.maxDebt(oraclePrice);
        safeTransferReceivedArgs.mintDebtOrProceedsTo = purchaser;
        safeTransferReceivedArgs.minOut = 0;
        vm.startPrank(purchaser);
        nft.safeTransferFrom(purchaser, address(strategy), collateralId + 1, abi.encode(safeTransferReceivedArgs));
        nft.safeTransferFrom(purchaser, address(strategy), collateralId + 2, abi.encode(safeTransferReceivedArgs));
        nft.safeTransferFrom(purchaser, address(strategy), collateralId + 3, abi.encode(safeTransferReceivedArgs));
        // purchaser now has 4.4... papr 
    }

    function test1() public {
        uint256 targetPurchasePrice = 4e18;
        // formula for how many seconds https://www.wolframalpha.com/input?i=solve+4+%3D+8.999+*+0.3+%5E+%28x+%2F+86400%29
        /// assumes 70% daily decay
        vm.warp(block.timestamp + 58187);
        // auctionStartPriceMultiplier = 3
        uint256 excess = strategy.auctionCurrentPrice(auction) - auction.startPrice / 3;
        emit log_uint(excess);
        uint256 penalty = excess * strategy.liquidationPenaltyBips() / 1e4;
        uint256 beforeBalance = strategy.perpetual().balanceOf(borrower);
        strategy.perpetual().approve(address(strategy), targetPurchasePrice);
        strategy.purchaseLiquidationAuctionNFT(auction, auction.startPrice, purchaser);
        uint256 afterBalance = strategy.perpetual().balanceOf(borrower);
        assertEq(afterBalance - beforeBalance, excess - penalty);
    }

    // if last NFT, sets to debt 0
    // if excess and has debt, applies to debt
    // if excess and no doubt, sends papr
    // 
}