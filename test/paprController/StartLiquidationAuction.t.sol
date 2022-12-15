// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.17;

import {ReservoirOracleUnderwriter} from "../../src/ReservoirOracleUnderwriter.sol";

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

    function testDeletesOwnerRecord() public {
        _makeMaxLoanLiquidatable();
        controller.startLiquidationAuction(borrower, collateral, oracleInfo);
        assertEq(controller.collateralOwner(collateral.addr, collateral.id), address(0));
    }

    function testRevertsIfNotLiquidatable() public {
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

    function testRevertsIfLiquidationsLocked() public {
        controller.setLiquidationsLocked(true);
        _makeMaxLoanLiquidatable();
        vm.expectRevert(IPaprController.LiquidationsLocked.selector);
        controller.startLiquidationAuction(address(0xded), collateral, oracleInfo);
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
