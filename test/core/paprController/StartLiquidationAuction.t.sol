// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ReservoirOracleUnderwriter} from "src/core/ReservoirOracleUnderwriter.sol";

import {BasePaprControllerTest} from "test/core/paprController/BasePaprController.ft.sol";
import {IPaprController} from "src/interfaces/IPaprController.sol";

contract StartLiquidationAuctionTest is BasePaprControllerTest {
    function setUp() public override {
        super.setUp();
        _openMaxLoanAndSwap();
        priceKind = ReservoirOracleUnderwriter.PriceKind.TWAP;
        oracleInfo = _getOracleInfoForCollateral(collateral.addr, underlying);
    }

    /// TODO sets start price correctly

    function testDrecrementsCollateralCountCorrectly() public {
        IPaprController.VaultInfo memory beforeInfo = strategy.vaultInfo(borrower, collateral.addr);
        _makeMaxLoanLiquidatable();
        strategy.startLiquidationAuction(borrower, collateral, oracleInfo);
        IPaprController.VaultInfo memory afterInfo = strategy.vaultInfo(borrower, collateral.addr);
        assertEq(beforeInfo.count - afterInfo.count, 1);
    }

    function testUpdatesLatestAuctionStartTime() public {
        _makeMaxLoanLiquidatable();
        strategy.startLiquidationAuction(borrower, collateral, oracleInfo);
        IPaprController.VaultInfo memory info = strategy.vaultInfo(borrower, collateral.addr);
        assertEq(info.latestAuctionStartTime, block.timestamp);
    }

    function testDeletesOwnerRecord() public {
        _makeMaxLoanLiquidatable();
        strategy.startLiquidationAuction(borrower, collateral, oracleInfo);
        assertEq(strategy.collateralOwner(collateral.addr, collateral.id), address(0));
    }

    function testRevertsIfNotLiquidatable() public {
        vm.expectRevert(IPaprController.NotLiquidatable.selector);
        strategy.startLiquidationAuction(borrower, collateral, oracleInfo);
    }

    function testRevertsIfInvalidCollateralAccountPair() public {
        _makeMaxLoanLiquidatable();
        vm.expectRevert(IPaprController.InvalidCollateralAccountPair.selector);
        strategy.startLiquidationAuction(address(0xded), collateral, oracleInfo);
    }

    function testRevertsIfAuctionOngoing() public {
        _makeMaxLoanLiquidatable();
        strategy.startLiquidationAuction(borrower, collateral, oracleInfo);

        nft.mint(borrower, collateralId + 1);
        vm.startPrank(borrower);
        nft.approve(address(strategy), collateralId + 1);
        strategy.addCollateral(IPaprController.Collateral(nft, collateralId + 1));

        vm.expectRevert(IPaprController.MinAuctionSpacing.selector);
        strategy.startLiquidationAuction(
            borrower, IPaprController.Collateral({id: collateralId + 1, addr: nft}), oracleInfo
        );
    }

    function testAllowsNewAuctionIfMinSpacingHasPassed() public {
        _makeMaxLoanLiquidatable();
        strategy.startLiquidationAuction(borrower, collateral, oracleInfo);

        nft.mint(borrower, collateralId + 1);
        vm.startPrank(borrower);
        nft.approve(address(strategy), collateralId + 1);
        strategy.addCollateral(IPaprController.Collateral(nft, collateralId + 1));

        vm.warp(block.timestamp + strategy.liquidationAuctionMinSpacing());
        oracleInfo = _getOracleInfoForCollateral(nft, underlying);
        strategy.startLiquidationAuction(
            borrower, IPaprController.Collateral({id: collateralId + 1, addr: nft}), oracleInfo
        );
    }
}
