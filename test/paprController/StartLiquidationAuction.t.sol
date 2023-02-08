// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.17;

import {ReservoirOracleUnderwriter} from "../../src/ReservoirOracleUnderwriter.sol";

import {INFTEDA} from "../../src/NFTEDA/extensions/NFTEDAStarterIncentive.sol";
import {BasePaprControllerTest} from "./BasePaprController.ft.sol";
import {IPaprController, ERC721} from "../../src/interfaces/IPaprController.sol";

contract StartLiquidationAuctionTest is BasePaprControllerTest {
    event RemoveCollateral(address indexed account, ERC721 indexed collateralAddress, uint256 indexed tokenId);

    function setUp() public override {
        super.setUp();
        _openMaxLoanAndSwap();
        priceKind = ReservoirOracleUnderwriter.PriceKind.TWAP;
        oracleInfo = _getOracleInfoForCollateral(collateral.addr, underlying);
    }

    function testDrecrementsCollateralCountCorrectly() public {
        IPaprController.VaultInfo memory beforeInfo = controller.vaultInfo(borrower, collateral.addr);
        _makeMaxLoanLiquidatable();
        controller.startLiquidationAuction(borrower, collateral, oracleInfo);
        IPaprController.VaultInfo memory afterInfo = controller.vaultInfo(borrower, collateral.addr);
        assertEq(beforeInfo.count - afterInfo.count, 1);
    }

    function testUpdatesLatestAuctionStartTime() public {
        _makeMaxLoanLiquidatable();
        controller.startLiquidationAuction(borrower, collateral, oracleInfo);
        IPaprController.VaultInfo memory info = controller.vaultInfo(borrower, collateral.addr);
        assertEq(info.latestAuctionStartTime, block.timestamp);
    }

    function testIncreasesAuctionCount() public {
        _makeMaxLoanLiquidatable();
        IPaprController.VaultInfo memory info = controller.vaultInfo(borrower, collateral.addr);
        controller.startLiquidationAuction(borrower, collateral, oracleInfo);
        assertEq(info.auctionCount + 1, controller.vaultInfo(borrower, collateral.addr).auctionCount);
    }

    function testStartsAtThreeTimesOraclePriceConvertedToPapr() public {
        _makeMaxLoanLiquidatable();
        INFTEDA.Auction memory auction = controller.startLiquidationAuction(borrower, collateral, oracleInfo);

        assertEq(auction.startPrice, oraclePrice * 3 * 1e18 / controller.target());
    }

    function testSetsLastAuctionPriceValuesCorrectly() public {
        _makeMaxLoanLiquidatable();
        INFTEDA.Auction memory auction = controller.startLiquidationAuction(borrower, collateral, oracleInfo);

        (uint40 t, uint216 p) = controller.lastAuctionStartPrice(collateral.addr);

        assertEq(auction.startPrice, p);
        assertEq(block.timestamp, t);
    }

    function testStartPriceDecreaseThrottled() public {
        _makeMaxLoanLiquidatable();
        controller.startLiquidationAuction(borrower, collateral, oracleInfo);
        (uint40 t, uint216 p) = controller.lastAuctionStartPrice(collateral.addr);

        address newBorrower = makeAddr("new borrower");
        nft.mint(newBorrower, collateralId + 1);
        vm.startPrank(newBorrower);
        nft.approve(address(controller), collateralId + 1);
        IPaprController.Collateral[] memory c = new IPaprController.Collateral[](1);
        c[0] = IPaprController.Collateral(nft, collateralId + 1);
        controller.addCollateral(c);
        priceKind = ReservoirOracleUnderwriter.PriceKind.LOWER;
        oracleInfo = _getOracleInfoForCollateral(collateral.addr, underlying);
        controller.increaseDebt(newBorrower, collateral.addr, controller.maxDebt(oraclePrice) - 1, oracleInfo);
        vm.warp(block.timestamp + 1 days);
        // lower oracle price where it should be throttled
        oraclePrice = oraclePrice * 0.3e18 / 1e18;
        priceKind = ReservoirOracleUnderwriter.PriceKind.TWAP;
        oracleInfo = _getOracleInfoForCollateral(collateral.addr, underlying);
        INFTEDA.Auction memory auction = controller.startLiquidationAuction(
            newBorrower, IPaprController.Collateral({id: collateralId + 1, addr: nft}), oracleInfo
        );

        uint256 maxPerSecondChange = 0.5e18 / uint256(1 days);
        uint256 min = p * (maxPerSecondChange * 1 days) / 1e18;
        assertEq(auction.startPrice, min);
        (t, p) = controller.lastAuctionStartPrice(collateral.addr);
        assertEq(min, p);
        assertEq(block.timestamp, t);
    }

    function testDeletesOwnerRecord() public {
        _makeMaxLoanLiquidatable();
        controller.startLiquidationAuction(borrower, collateral, oracleInfo);
        assertEq(controller.collateralOwner(collateral.addr, collateral.id), address(0));
    }

    function testRevertsIfDebtLessThanMax() public {
        vm.expectRevert(IPaprController.NotLiquidatable.selector);
        controller.startLiquidationAuction(borrower, collateral, oracleInfo);
    }

    function testRevertsIfDebtEqualToMax() public {
        nft.mint(borrower, 2);
        /// manually calc what maxDebt would be after 1 week
        safeTransferReceivedArgs.debt = 1.498207072170842e18 - 163;
        safeTransferReceivedArgs.swapParams.amount = 0;
        safeTransferReceivedArgs.swapParams.minOut = 0;
        vm.prank(borrower);
        nft.safeTransferFrom(borrower, address(controller), 2, abi.encode(safeTransferReceivedArgs));
        vm.warp(block.timestamp + 1 weeks);
        oracleInfo = _getOracleInfoForCollateral(collateral.addr, underlying);
        assertEq(controller.vaultInfo(borrower, collateral.addr).debt, controller.maxDebt(oraclePrice * 2));
        assertEq(controller.vaultInfo(borrower, collateral.addr).count, 2);
        vm.expectRevert(IPaprController.NotLiquidatable.selector);
        controller.startLiquidationAuction(borrower, collateral, oracleInfo);
    }

    function testRevertsIfInvalidCollateralAccountPair() public {
        _makeMaxLoanLiquidatable();
        vm.expectRevert(IPaprController.InvalidCollateralAccountPair.selector);
        controller.startLiquidationAuction(address(0xded), collateral, oracleInfo);
    }

    function testRevertsIfWrongPriceTypeFromOracle() public {
        _makeMaxLoanLiquidatable();
        priceKind = ReservoirOracleUnderwriter.PriceKind.LOWER;
        oracleInfo = _getOracleInfoForCollateral(collateral.addr, underlying);
        vm.expectRevert(ReservoirOracleUnderwriter.WrongIdentifierFromOracleMessage.selector);
        controller.startLiquidationAuction(borrower, collateral, oracleInfo);
    }

    function testRevertsIfAuctionOngoing() public {
        _makeMaxLoanLiquidatable();
        controller.startLiquidationAuction(borrower, collateral, oracleInfo);

        nft.mint(borrower, collateralId + 1);
        vm.startPrank(borrower);
        nft.approve(address(controller), collateralId + 1);
        IPaprController.Collateral[] memory c = new IPaprController.Collateral[](1);
        c[0] = IPaprController.Collateral(nft, collateralId + 1);
        controller.addCollateral(c);
        vm.expectRevert(IPaprController.MinAuctionSpacing.selector);
        controller.startLiquidationAuction(
            borrower, IPaprController.Collateral({id: collateralId + 1, addr: nft}), oracleInfo
        );
    }

    function testAllowsNewAuctionIfMinSpacingHasPassed() public {
        _makeMaxLoanLiquidatable();
        controller.startLiquidationAuction(borrower, collateral, oracleInfo);

        nft.mint(borrower, collateralId + 1);
        vm.startPrank(borrower);
        nft.approve(address(controller), collateralId + 1);
        IPaprController.Collateral[] memory c = new IPaprController.Collateral[](1);
        c[0] = IPaprController.Collateral(nft, collateralId + 1);
        controller.addCollateral(c);

        vm.warp(block.timestamp + controller.liquidationAuctionMinSpacing());
        oracleInfo = _getOracleInfoForCollateral(nft, underlying);
        controller.startLiquidationAuction(
            borrower, IPaprController.Collateral({id: collateralId + 1, addr: nft}), oracleInfo
        );
    }

    function testEmitsRemoveCollateral() public {
        _makeMaxLoanLiquidatable();
        vm.expectEmit(true, true, true, false);
        emit RemoveCollateral(borrower, collateral.addr, collateral.id);
        controller.startLiquidationAuction(borrower, collateral, oracleInfo);
    }
}
