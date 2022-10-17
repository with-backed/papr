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
        // trade for papr 
    }

    function test1() public {
        // strategy.purchaseLiquidationAuctionNFT(auction, auction.startPrice, );
    }

    // if last NFT, sets to debt 0
    // if excess and has debt, applies to debt
    // if excess and no doubt, sends papr
    // 
}