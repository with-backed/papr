// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ReservoirOracleUnderwriter} from "src/ReservoirOracleUnderwriter.sol";
import {INFTEDA} from "NFTEDA/extensions/NFTEDAStarterIncentive.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";

import {BasePaprControllerTest} from "test/paprController/BasePaprController.ft.sol";
import {IPaprController} from "src/interfaces/IPaprController.sol";

contract PurchaseLiquidationAuctionNFT is BasePaprControllerTest {
    event ReduceDebt(address indexed account, ERC721 indexed collateralAddress, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 amount);

    INFTEDA.Auction auction;
    address purchaser = address(2);

    function setUp() public override {
        super.setUp();
        _openMaxLoanAndSwap();
        _makeMaxLoanLiquidatable();
        safeTransferReceivedArgs.oracleInfo = oracleInfo;
        priceKind = ReservoirOracleUnderwriter.PriceKind.TWAP;
        oracleInfo = _getOracleInfoForCollateral(collateral.addr, underlying);
        auction = strategy.startLiquidationAuction(borrower, collateral, oracleInfo);
        emit log_uint(strategy.auctionCurrentPrice(auction));
        nft.mint(purchaser, collateralId + 1);
        nft.mint(purchaser, collateralId + 2);
        nft.mint(purchaser, collateralId + 3);
        safeTransferReceivedArgs.debt = strategy.maxDebt(oraclePrice) - 10;
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
        oracleInfo = _getOracleInfoForCollateral(collateral.addr, underlying);
        IPaprController.VaultInfo memory info = strategy.vaultInfo(borrower, collateral.addr);
        uint256 neededToSave = 0;
        uint256 excess = strategy.auctionCurrentPrice(auction) - neededToSave;
        uint256 penalty = excess * strategy.liquidationPenaltyBips() / 1e4;
        uint256 credit = excess - penalty;
        uint256 expectedPayout = credit - (info.debt - neededToSave);
        uint256 beforeBalance = strategy.perpetual().balanceOf(borrower);
        strategy.perpetual().approve(address(strategy), auction.startPrice);
        assertGt(strategy.auctionCurrentPrice(auction), 0);
        emit log_uint(strategy.auctionCurrentPrice(auction));
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(purchaser), address(strategy), strategy.auctionCurrentPrice(auction));
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(strategy), address(0), penalty);
        vm.expectEmit(true, false, false, true);
        emit ReduceDebt(borrower, collateral.addr, info.debt);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(strategy), address(0), info.debt);
        strategy.purchaseLiquidationAuctionNFT(auction, auction.startPrice, purchaser, oracleInfo);
        uint256 afterBalance = strategy.perpetual().balanceOf(borrower);
        assertGt(afterBalance, beforeBalance);
        assertEq(afterBalance - beforeBalance, expectedPayout);
        info = strategy.vaultInfo(borrower, collateral.addr);
        assertEq(info.debt, 0);
    }

    function testWhenLastNFTAndShortfall() public {
        // https://www.wolframalpha.com/input?i=solve+1.5+%3D+8.999+*+0.3+%5E+%28x+%2F+86400%29
        vm.warp(block.timestamp + 128575);
        oracleInfo = _getOracleInfoForCollateral(collateral.addr, underlying);
        uint256 beforeBalance = strategy.perpetual().balanceOf(borrower);
        strategy.perpetual().approve(address(strategy), auction.startPrice);
        uint256 price = strategy.auctionCurrentPrice(auction);
        uint256 penalty = price * strategy.liquidationPenaltyBips() / 1e4;
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(strategy), address(0), penalty);
        vm.expectEmit(true, false, false, true);
        emit ReduceDebt(borrower, collateral.addr, price - penalty);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(strategy), address(0), price - penalty);
        IPaprController.VaultInfo memory info = strategy.vaultInfo(borrower, collateral.addr);
        // burning debt not covered by auction
        vm.expectEmit(true, false, false, true);
        emit ReduceDebt(borrower, collateral.addr, info.debt - (price - penalty));
        strategy.purchaseLiquidationAuctionNFT(auction, auction.startPrice, purchaser, oracleInfo);
        uint256 afterBalance = strategy.perpetual().balanceOf(borrower);
        assertEq(afterBalance, beforeBalance);
        info = strategy.vaultInfo(borrower, collateral.addr);
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
        strategy.addCollateral(collateral);
        vm.stopPrank();
        vm.startPrank(purchaser);

        /// https://www.wolframalpha.com/input?i=solve+4+%3D+8.999+*+0.3+%5E+%28x+%2F+86400%29
        vm.warp(block.timestamp + 58187);
        oracleInfo = _getOracleInfoForCollateral(collateral.addr, underlying);
        IPaprController.VaultInfo memory info = strategy.vaultInfo(borrower, collateral.addr);
        uint256 neededToSave = info.debt - strategy.maxDebt(oraclePrice);
        uint256 excess = strategy.auctionCurrentPrice(auction) - neededToSave;
        uint256 penalty = excess * strategy.liquidationPenaltyBips() / 1e4;
        uint256 credit = excess - penalty;
        uint256 expectedPayout = credit - (info.debt - neededToSave);
        uint256 beforeBalance = strategy.perpetual().balanceOf(borrower);
        strategy.perpetual().approve(address(strategy), auction.startPrice);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(strategy), address(0), penalty);
        vm.expectEmit(true, false, false, true);
        emit ReduceDebt(borrower, collateral.addr, info.debt);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(strategy), address(0), info.debt);
        strategy.purchaseLiquidationAuctionNFT(auction, auction.startPrice, purchaser, oracleInfo);
        uint256 afterBalance = strategy.perpetual().balanceOf(borrower);
        assertGt(afterBalance, beforeBalance);
        assertEq(afterBalance - beforeBalance, expectedPayout);
        info = strategy.vaultInfo(borrower, collateral.addr);
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
        strategy.addCollateral(collateral);
        vm.stopPrank();
        vm.startPrank(purchaser);

        // https://www.wolframalpha.com/input?i=solve+1.5+%3D+8.999+*+0.3+%5E+%28x+%2F+86400%29
        vm.warp(block.timestamp + 128575);
        oracleInfo = _getOracleInfoForCollateral(collateral.addr, underlying);
        IPaprController.VaultInfo memory beforeInfo = strategy.vaultInfo(borrower, collateral.addr);
        uint256 beforeBalance = strategy.perpetual().balanceOf(borrower);
        strategy.perpetual().approve(address(strategy), auction.startPrice);
        uint256 neededToSave = beforeInfo.debt - strategy.maxDebt(oraclePrice * beforeInfo.count);
        uint256 excess = strategy.auctionCurrentPrice(auction) - neededToSave;
        uint256 penalty = excess * strategy.liquidationPenaltyBips() / 1e4;
        uint256 credit = excess - penalty + neededToSave;
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(strategy), address(0), penalty);
        vm.expectEmit(true, false, false, true);
        emit ReduceDebt(borrower, collateral.addr, credit);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(strategy), address(0), credit);
        strategy.purchaseLiquidationAuctionNFT(auction, auction.startPrice, purchaser, oracleInfo);
        uint256 afterBalance = strategy.perpetual().balanceOf(borrower);
        assertEq(afterBalance, beforeBalance);
        IPaprController.VaultInfo memory info = strategy.vaultInfo(borrower, collateral.addr);
        assertEq(info.debt, beforeInfo.debt - credit);
    }

    function testWhenNoExcess() public {
        vm.stopPrank();
        // add collateral
        uint256 tokenId = collateralId + 5;
        nft.mint(borrower, tokenId);
        vm.startPrank(borrower);
        nft.approve(address(strategy), tokenId);
        collateral.id = tokenId;
        strategy.addCollateral(collateral);
        vm.stopPrank();
        vm.startPrank(purchaser);

        vm.warp(block.timestamp + 2 weeks);
        oracleInfo = _getOracleInfoForCollateral(collateral.addr, underlying);
        IPaprController.VaultInfo memory beforeInfo = strategy.vaultInfo(borrower, collateral.addr);
        uint256 neededToSave = beforeInfo.debt - strategy.maxDebt(oraclePrice * beforeInfo.count);
        uint256 price = strategy.auctionCurrentPrice(auction);
        // there will no excess
        assertGt(neededToSave, price);
        strategy.perpetual().approve(address(strategy), auction.startPrice);
        vm.expectEmit(true, false, false, true);
        emit ReduceDebt(borrower, collateral.addr, price);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(strategy), address(0), price);
        strategy.purchaseLiquidationAuctionNFT(auction, auction.startPrice, purchaser, oracleInfo);
        IPaprController.VaultInfo memory afterInfo = strategy.vaultInfo(borrower, collateral.addr);
        assertEq(beforeInfo.debt - afterInfo.debt, price);
    }

    /// @note we do not test noExcess and last collateral because the contract considers any amount
    /// to be excess
}
