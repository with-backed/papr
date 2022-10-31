// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseLendingStrategyTest} from "test/core/lendingStrategy/BaseLendingStrategy.ft.sol";
import {ILendingStrategy} from "src/interfaces/ILendingStrategy.sol";

contract StartLiquidationAuctionTest is BaseLendingStrategyTest {
    function setUp() public override {
        super.setUp();
        _openMaxLoanAndSwap();
    }

    /// TODO sets start price correctly

    function testDecrementsVaultsCollateralValue() public {
        ILendingStrategy.VaultInfo memory info = strategy.vaultInfo(borrower);
        assertEq(info.collateralValue, oraclePrice);
        _makeMaxLoanLiquidatable();
        strategy.startLiquidationAuction(borrower, collateral);
        info = strategy.vaultInfo(borrower);
        assertEq(info.collateralValue, 0);
    }

    function testUpdatesLatestAuctionStartTime() public {
        _makeMaxLoanLiquidatable();
        strategy.startLiquidationAuction(borrower, collateral);
        ILendingStrategy.VaultInfo memory info = strategy.vaultInfo(borrower);
        assertEq(info.latestAuctionStartTime, block.timestamp);
    }

    function testDeletesFrozenOracleValuation() public {
        bytes32 h = strategy.collateralHash(collateral, borrower);
        uint256 valuation = strategy.collateralFrozenOraclePrice(h);
        assertEq(valuation, oraclePrice);
        _makeMaxLoanLiquidatable();
        strategy.startLiquidationAuction(borrower, collateral);
        valuation = strategy.collateralFrozenOraclePrice(h);
        assertEq(valuation, 0);
    }

    function testRevertsIfNotLiquidatable() public {
        vm.expectRevert(ILendingStrategy.NotLiquidatable.selector);
        strategy.startLiquidationAuction(borrower, collateral);
    }

    function testRevertsIfInvalidCollateralAccountPair() public {
        _makeMaxLoanLiquidatable();
        vm.expectRevert(ILendingStrategy.InvalidCollateralAccountPair.selector);
        strategy.startLiquidationAuction(address(0xded), collateral);
    }

    function testRevertsIfAuctionOngoing() public {
        _makeMaxLoanLiquidatable();
        strategy.startLiquidationAuction(borrower, collateral);

        nft.mint(borrower, collateralId + 1);
        vm.startPrank(borrower);
        nft.approve(address(strategy), collateralId + 1);
        strategy.addCollateral(ILendingStrategy.Collateral(nft, collateralId + 1), oracleInfo);

        vm.expectRevert(ILendingStrategy.MinAuctionSpacing.selector);
        strategy.startLiquidationAuction(borrower, ILendingStrategy.Collateral({id: collateralId + 1, addr: nft}));
    }

    function testAllowsNewAuctionIfMinSpacingHasPassed() public {
        _makeMaxLoanLiquidatable();
        strategy.startLiquidationAuction(borrower, collateral);

        nft.mint(borrower, collateralId + 1);
        vm.startPrank(borrower);
        nft.approve(address(strategy), collateralId + 1);
        strategy.addCollateral(ILendingStrategy.Collateral(nft, collateralId + 1), oracleInfo);

        vm.warp(block.timestamp + strategy.liquidationAuctionMinSpacing());
        strategy.startLiquidationAuction(borrower, ILendingStrategy.Collateral({id: collateralId + 1, addr: nft}));
    }
}
