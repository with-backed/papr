// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ReservoirOracleUnderwriter} from "src/core/ReservoirOracleUnderwriter.sol";

import {BaseLendingStrategyTest} from "test/core/lendingStrategy/BaseLendingStrategy.ft.sol";
import {ILendingStrategy} from "src/interfaces/ILendingStrategy.sol";

contract StartLiquidationAuctionTest is BaseLendingStrategyTest {
    function setUp() public override {
        super.setUp();
        _openMaxLoanAndSwap();
        priceKind = ReservoirOracleUnderwriter.PriceKind.TWAP;
        oracleInfo = _getOracleInfoForCollateral(collateral.addr, underlying);
    }

    /// TODO sets start price correctly

    function testDrecrementsCollateralCountCorrectly() public {
        ILendingStrategy.VaultInfo memory beforeInfo = strategy.vaultInfo(borrower, collateral.addr);
        _makeMaxLoanLiquidatable();
        strategy.startLiquidationAuction(borrower, collateral, oracleInfo);
        ILendingStrategy.VaultInfo memory afterInfo = strategy.vaultInfo(borrower, collateral.addr);
        assertEq(beforeInfo.count - afterInfo.count, 1);
    }

    function testUpdatesLatestAuctionStartTime() public {
        _makeMaxLoanLiquidatable();
        strategy.startLiquidationAuction(borrower, collateral, oracleInfo);
        ILendingStrategy.VaultInfo memory info = strategy.vaultInfo(borrower, collateral.addr);
        assertEq(info.latestAuctionStartTime, block.timestamp);
    }

    function testDeletesOwnerRecord() public {
        _makeMaxLoanLiquidatable();
        strategy.startLiquidationAuction(borrower, collateral, oracleInfo);
        assertEq(strategy.collateralOwner(collateral.addr, collateral.id), address(0));
    }

    function testRevertsIfNotLiquidatable() public {
        vm.expectRevert(ILendingStrategy.NotLiquidatable.selector);
        strategy.startLiquidationAuction(borrower, collateral, oracleInfo);
    }

    function testRevertsIfInvalidCollateralAccountPair() public {
        _makeMaxLoanLiquidatable();
        vm.expectRevert(ILendingStrategy.InvalidCollateralAccountPair.selector);
        strategy.startLiquidationAuction(address(0xded), collateral, oracleInfo);
    }

    function testRevertsIfAuctionOngoing() public {
        _makeMaxLoanLiquidatable();
        strategy.startLiquidationAuction(borrower, collateral, oracleInfo);

        nft.mint(borrower, collateralId + 1);
        vm.startPrank(borrower);
        nft.approve(address(strategy), collateralId + 1);
        strategy.addCollateral(ILendingStrategy.Collateral(nft, collateralId + 1));

        vm.expectRevert(ILendingStrategy.MinAuctionSpacing.selector);
        strategy.startLiquidationAuction(
            borrower, ILendingStrategy.Collateral({id: collateralId + 1, addr: nft}), oracleInfo
        );
    }

    function testAllowsNewAuctionIfMinSpacingHasPassed() public {
        _makeMaxLoanLiquidatable();
        strategy.startLiquidationAuction(borrower, collateral, oracleInfo);

        nft.mint(borrower, collateralId + 1);
        vm.startPrank(borrower);
        nft.approve(address(strategy), collateralId + 1);
        strategy.addCollateral(ILendingStrategy.Collateral(nft, collateralId + 1));

        vm.warp(block.timestamp + strategy.liquidationAuctionMinSpacing());
        strategy.startLiquidationAuction(
            borrower, ILendingStrategy.Collateral({id: collateralId + 1, addr: nft}), oracleInfo
        );
    }
}
