// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {INFTEDA} from "NFTEDA/extensions/NFTEDAStarterIncentive.sol";

import {BaseLendingStrategyTest} from "test/core/lendingStrategy/BaseLendingStrategy.ft.sol";
import {ILendingStrategy} from "src/interfaces/ILendingStrategy.sol";

contract PurchaseLiquidationAuctionNFT is BaseLendingStrategyTest {
    event ReduceDebt(address indexed account, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 amount);

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

    /// when last NFT in vault

    function testWhenLastNFTAndSurplus() public {
        /// https://www.wolframalpha.com/input?i=solve+4+%3D+8.999+*+0.3+%5E+%28x+%2F+86400%29
        vm.warp(block.timestamp + 58187);
        ILendingStrategy.VaultInfo memory info = strategy.vaultInfo(borrower);
        uint256 neededToSave = 0;
        uint256 excess = strategy.auctionCurrentPrice(auction) - neededToSave;
        uint256 penalty = excess * strategy.liquidationPenaltyBips() / 1e4;
        uint256 credit = excess - penalty;
        uint256 expectedPayout = credit - (info.debt - neededToSave);
        uint256 beforeBalance = strategy.perpetual().balanceOf(borrower);
        strategy.perpetual().approve(address(strategy), auction.startPrice);
        vm.expectEmit(true, false, false, true);
        emit ReduceDebt(borrower, info.debt);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(strategy), address(0), info.debt);
        strategy.purchaseLiquidationAuctionNFT(auction, auction.startPrice, purchaser);
        uint256 afterBalance = strategy.perpetual().balanceOf(borrower);
        assertGt(afterBalance, beforeBalance);
        assertEq(afterBalance - beforeBalance, expectedPayout);
        info = strategy.vaultInfo(borrower);
        assertEq(info.debt, 0);
    }

    function testWhenLastNFTAndShortfall() public {
        // https://www.wolframalpha.com/input?i=solve+1.5+%3D+8.999+*+0.3+%5E+%28x+%2F+86400%29
        vm.warp(block.timestamp + 128575);
        uint256 beforeBalance = strategy.perpetual().balanceOf(borrower);
        strategy.perpetual().approve(address(strategy), auction.startPrice);
        uint256 price = strategy.auctionCurrentPrice(auction);
        uint256 penalty = price * strategy.liquidationPenaltyBips() / 1e4;
        vm.expectEmit(true, false, false, true);
        emit ReduceDebt(borrower, price - penalty);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(strategy), address(0), price - penalty);
        ILendingStrategy.VaultInfo memory info = strategy.vaultInfo(borrower);
        // burning debt not covered by auction
        vm.expectEmit(true, false, false, true);
        emit ReduceDebt(borrower, info.debt - (price - penalty));
        strategy.purchaseLiquidationAuctionNFT(auction, auction.startPrice, purchaser);
        uint256 afterBalance = strategy.perpetual().balanceOf(borrower);
        assertEq(afterBalance, beforeBalance);
        info = strategy.vaultInfo(borrower);
        assertEq(info.debt, 0);
    }

    function testWhenNotLastNFTAndSurplus() public {
        // add collateral
        uint256 tokenId = collateralId + 5;
        nft.mint(borrower, tokenId);
        vm.stopPrank();
        vm.startPrank(borrower);
        nft.approve(address(strategy), tokenId);
        collateral.id = tokenId;
        strategy.addCollateral(collateral, oracleInfo);
        vm.stopPrank();
        vm.startPrank(purchaser);

        /// https://www.wolframalpha.com/input?i=solve+4+%3D+8.999+*+0.3+%5E+%28x+%2F+86400%29
        vm.warp(block.timestamp + 58187);
        ILendingStrategy.VaultInfo memory info = strategy.vaultInfo(borrower);
        uint256 neededToSave = info.debt - strategy.maxDebt(info.collateralValue);
        uint256 excess = strategy.auctionCurrentPrice(auction) - neededToSave;
        uint256 penalty = excess * strategy.liquidationPenaltyBips() / 1e4;
        uint256 credit = excess - penalty;
        uint256 expectedPayout = credit - (info.debt - neededToSave);
        uint256 beforeBalance = strategy.perpetual().balanceOf(borrower);
        strategy.perpetual().approve(address(strategy), auction.startPrice);
        vm.expectEmit(true, false, false, true);
        emit ReduceDebt(borrower, info.debt);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(strategy), address(0), info.debt);
        strategy.purchaseLiquidationAuctionNFT(auction, auction.startPrice, purchaser);
        uint256 afterBalance = strategy.perpetual().balanceOf(borrower);
        assertGt(afterBalance, beforeBalance);
        assertEq(afterBalance - beforeBalance, expectedPayout);
        info = strategy.vaultInfo(borrower);
        assertEq(info.debt, 0);
    }

    function testWhenNotLastNFTAndShortfall() public {
        // add collateral
        uint256 tokenId = collateralId + 5;
        nft.mint(borrower, tokenId);
        vm.stopPrank();
        vm.startPrank(borrower);
        nft.approve(address(strategy), tokenId);
        collateral.id = tokenId;
        strategy.addCollateral(collateral, oracleInfo);
        vm.stopPrank();
        vm.startPrank(purchaser);

        // https://www.wolframalpha.com/input?i=solve+1.5+%3D+8.999+*+0.3+%5E+%28x+%2F+86400%29
        vm.warp(block.timestamp + 128575);
        ILendingStrategy.VaultInfo memory beforeInfo = strategy.vaultInfo(borrower);
        uint256 beforeBalance = strategy.perpetual().balanceOf(borrower);
        strategy.perpetual().approve(address(strategy), auction.startPrice);
        uint256 neededToSave = beforeInfo.debt - strategy.maxDebt(beforeInfo.collateralValue);
        uint256 excess = strategy.auctionCurrentPrice(auction) - neededToSave;
        uint256 penalty = excess * strategy.liquidationPenaltyBips() / 1e4;
        uint256 credit = excess - penalty + neededToSave;
        vm.expectEmit(true, false, false, true);
        emit ReduceDebt(borrower, credit);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(strategy), address(0), credit);
        strategy.purchaseLiquidationAuctionNFT(auction, auction.startPrice, purchaser);
        uint256 afterBalance = strategy.perpetual().balanceOf(borrower);
        assertEq(afterBalance, beforeBalance);
        ILendingStrategy.VaultInfo memory info = strategy.vaultInfo(borrower);
        assertEq(info.debt, beforeInfo.debt - credit);
    }
}
