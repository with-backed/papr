// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ReservoirOracleUnderwriter} from "src/ReservoirOracleUnderwriter.sol";
import {INFTEDA} from "src/NFTEDA/extensions/NFTEDAStarterIncentive.sol";
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
        auction = controller.startLiquidationAuction(borrower, collateral, oracleInfo);
        nft.mint(purchaser, collateralId + 1);
        nft.mint(purchaser, collateralId + 2);
        nft.mint(purchaser, collateralId + 3);
        safeTransferReceivedArgs.debt = controller.maxDebt(oraclePrice) - 10;
        safeTransferReceivedArgs.proceedsTo = purchaser;
        safeTransferReceivedArgs.swapParams.minOut = 0;
        vm.startPrank(purchaser);
        nft.safeTransferFrom(purchaser, address(controller), collateralId + 1, abi.encode(safeTransferReceivedArgs));
        nft.safeTransferFrom(purchaser, address(controller), collateralId + 2, abi.encode(safeTransferReceivedArgs));
        nft.safeTransferFrom(purchaser, address(controller), collateralId + 3, abi.encode(safeTransferReceivedArgs));
        // purchaser now has 4.4... papr
    }

    /// when last NFT in vault

    function testWhenLastNFTAndSurplus() public {
        /// https://www.wolframalpha.com/input?i=solve+4+%3D+8.999+*+0.3+%5E+%28x+%2F+86400%29
        vm.warp(block.timestamp + 58187);
        oracleInfo = _getOracleInfoForCollateral(collateral.addr, underlying);
        IPaprController.VaultInfo memory info = controller.vaultInfo(borrower, collateral.addr);
        uint256 neededToSave = 0;
        uint256 excess = controller.auctionCurrentPrice(auction) - neededToSave;
        uint256 penalty = excess * controller.liquidationPenaltyBips() / 1e4;
        uint256 credit = excess - penalty;
        uint256 expectedPayout = credit - (info.debt - neededToSave);
        uint256 beforeBalance = controller.papr().balanceOf(borrower);
        controller.papr().approve(address(controller), auction.startPrice);
        assertGt(controller.auctionCurrentPrice(auction), 0);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(purchaser), address(controller), controller.auctionCurrentPrice(auction));
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(controller), address(0), penalty);
        vm.expectEmit(true, false, false, true);
        emit ReduceDebt(borrower, collateral.addr, info.debt);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(controller), address(0), info.debt);
        controller.purchaseLiquidationAuctionNFT(auction, auction.startPrice, purchaser, oracleInfo);
        uint256 afterBalance = controller.papr().balanceOf(borrower);
        assertGt(afterBalance, beforeBalance);
        assertEq(afterBalance - beforeBalance, expectedPayout);
        info = controller.vaultInfo(borrower, collateral.addr);
        assertEq(info.debt, 0);
    }

    function testWhenLastNFTAndShortfall() public {
        // https://www.wolframalpha.com/input?i=solve+1.5+%3D+8.999+*+0.3+%5E+%28x+%2F+86400%29
        vm.warp(block.timestamp + 128575);
        oracleInfo = _getOracleInfoForCollateral(collateral.addr, underlying);
        uint256 beforeBalance = controller.papr().balanceOf(borrower);
        controller.papr().approve(address(controller), auction.startPrice);
        uint256 price = controller.auctionCurrentPrice(auction);
        uint256 penalty = price * controller.liquidationPenaltyBips() / 1e4;
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(controller), address(0), penalty);
        vm.expectEmit(true, false, false, true);
        emit ReduceDebt(borrower, collateral.addr, price - penalty);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(controller), address(0), price - penalty);
        IPaprController.VaultInfo memory info = controller.vaultInfo(borrower, collateral.addr);
        // burning debt not covered by auction
        vm.expectEmit(true, false, false, true);
        emit ReduceDebt(borrower, collateral.addr, info.debt - (price - penalty));
        controller.purchaseLiquidationAuctionNFT(auction, auction.startPrice, purchaser, oracleInfo);
        uint256 afterBalance = controller.papr().balanceOf(borrower);
        assertEq(afterBalance, beforeBalance);
        info = controller.vaultInfo(borrower, collateral.addr);
        assertEq(info.debt, 0);
    }

    function testWhenNotLastNFTAndSurplus() public {
        // add collateral
        uint256 tokenId = collateralId + 5;
        nft.mint(borrower, tokenId);
        vm.stopPrank();
        vm.startPrank(borrower);
        nft.approve(address(controller), tokenId);
        collateral.id = tokenId;
        controller.addCollateral(collateral);
        vm.stopPrank();
        vm.startPrank(purchaser);

        /// https://www.wolframalpha.com/input?i=solve+4+%3D+8.999+*+0.3+%5E+%28x+%2F+86400%29
        vm.warp(block.timestamp + 58187);
        oracleInfo = _getOracleInfoForCollateral(collateral.addr, underlying);
        IPaprController.VaultInfo memory info = controller.vaultInfo(borrower, collateral.addr);
        uint256 neededToSave = info.debt - controller.maxDebt(oraclePrice);
        uint256 excess = controller.auctionCurrentPrice(auction) - neededToSave;
        uint256 penalty = excess * controller.liquidationPenaltyBips() / 1e4;
        uint256 credit = excess - penalty;
        uint256 expectedPayout = credit - (info.debt - neededToSave);
        uint256 beforeBalance = controller.papr().balanceOf(borrower);
        controller.papr().approve(address(controller), auction.startPrice);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(controller), address(0), penalty);
        vm.expectEmit(true, false, false, true);
        emit ReduceDebt(borrower, collateral.addr, info.debt);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(controller), address(0), info.debt);
        controller.purchaseLiquidationAuctionNFT(auction, auction.startPrice, purchaser, oracleInfo);
        uint256 afterBalance = controller.papr().balanceOf(borrower);
        assertGt(afterBalance, beforeBalance);
        assertEq(afterBalance - beforeBalance, expectedPayout);
        info = controller.vaultInfo(borrower, collateral.addr);
        assertEq(info.debt, 0);
    }

    function testWhenNotLastNFTAndShortfall() public {
        // add collateral
        uint256 tokenId = collateralId + 5;
        nft.mint(borrower, tokenId);
        vm.stopPrank();
        vm.startPrank(borrower);
        nft.approve(address(controller), tokenId);
        collateral.id = tokenId;
        controller.addCollateral(collateral);
        vm.stopPrank();
        vm.startPrank(purchaser);

        // https://www.wolframalpha.com/input?i=solve+1.5+%3D+8.999+*+0.3+%5E+%28x+%2F+86400%29
        vm.warp(block.timestamp + 128575);
        oracleInfo = _getOracleInfoForCollateral(collateral.addr, underlying);
        IPaprController.VaultInfo memory beforeInfo = controller.vaultInfo(borrower, collateral.addr);
        uint256 beforeBalance = controller.papr().balanceOf(borrower);
        controller.papr().approve(address(controller), auction.startPrice);
        uint256 neededToSave = beforeInfo.debt - controller.maxDebt(oraclePrice * beforeInfo.count);
        uint256 excess = controller.auctionCurrentPrice(auction) - neededToSave;
        uint256 penalty = excess * controller.liquidationPenaltyBips() / 1e4;
        uint256 credit = excess - penalty + neededToSave;
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(controller), address(0), penalty);
        vm.expectEmit(true, false, false, true);
        emit ReduceDebt(borrower, collateral.addr, credit);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(controller), address(0), credit);
        controller.purchaseLiquidationAuctionNFT(auction, auction.startPrice, purchaser, oracleInfo);
        uint256 afterBalance = controller.papr().balanceOf(borrower);
        assertEq(afterBalance, beforeBalance);
        IPaprController.VaultInfo memory info = controller.vaultInfo(borrower, collateral.addr);
        assertEq(info.debt, beforeInfo.debt - credit);
    }

    function testWhenNoExcess() public {
        vm.stopPrank();
        // add collateral
        uint256 tokenId = collateralId + 5;
        nft.mint(borrower, tokenId);
        vm.startPrank(borrower);
        nft.approve(address(controller), tokenId);
        collateral.id = tokenId;
        controller.addCollateral(collateral);
        vm.stopPrank();
        vm.startPrank(purchaser);

        vm.warp(block.timestamp + 2 weeks);
        oracleInfo = _getOracleInfoForCollateral(collateral.addr, underlying);
        IPaprController.VaultInfo memory beforeInfo = controller.vaultInfo(borrower, collateral.addr);
        uint256 neededToSave = beforeInfo.debt - controller.maxDebt(oraclePrice * beforeInfo.count);
        uint256 price = controller.auctionCurrentPrice(auction);
        // there will no excess
        assertGt(neededToSave, price);
        controller.papr().approve(address(controller), auction.startPrice);
        vm.expectEmit(true, false, false, true);
        emit ReduceDebt(borrower, collateral.addr, price);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(controller), address(0), price);
        controller.purchaseLiquidationAuctionNFT(auction, auction.startPrice, purchaser, oracleInfo);
        IPaprController.VaultInfo memory afterInfo = controller.vaultInfo(borrower, collateral.addr);
        assertEq(beforeInfo.debt - afterInfo.debt, price);
    }

    /// @dev we do not test noExcess and last collateral because the contract considers any amount
    /// to be excess

    function testResetsLatestAuctionStartTimeIfLatestAuction() public {
        vm.warp(block.timestamp + 58187);
        oracleInfo = _getOracleInfoForCollateral(collateral.addr, underlying);
        controller.papr().approve(address(controller), auction.startPrice);
        controller.purchaseLiquidationAuctionNFT(auction, auction.startPrice, purchaser, oracleInfo);
        assertEq(0, controller.vaultInfo(borrower, collateral.addr).latestAuctionStartTime);
    }

    function testDoesNotResetLatestAuctionStartTimeIfLatestAuction() public {
        // add collateral
        uint256 tokenId = collateralId + 5;
        nft.mint(borrower, tokenId);
        vm.stopPrank();
        vm.startPrank(borrower);
        nft.approve(address(controller), tokenId);
        collateral.id = tokenId;
        controller.addCollateral(collateral);
        // start new auction
        uint256 expectedTimestamp = block.timestamp + 2 days;
        vm.warp(expectedTimestamp); // min auction sapcing
        oracleInfo = _getOracleInfoForCollateral(collateral.addr, underlying);
        controller.startLiquidationAuction(borrower, collateral, oracleInfo);
        vm.stopPrank();
        vm.startPrank(purchaser);
        //
        vm.warp(block.timestamp + 58187);
        oracleInfo = _getOracleInfoForCollateral(collateral.addr, underlying);
        controller.papr().approve(address(controller), auction.startPrice);
        controller.purchaseLiquidationAuctionNFT(auction, auction.startPrice, purchaser, oracleInfo);
        assertEq(expectedTimestamp, controller.vaultInfo(borrower, collateral.addr).latestAuctionStartTime);
    }
}
