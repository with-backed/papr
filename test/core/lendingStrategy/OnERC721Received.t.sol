// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseLendingStrategyTest} from "test/core/lendingStrategy/BaseLendingStrategy.ft.sol";
import {ILendingStrategy} from "src/interfaces/ILendingStrategy.sol";
import {LendingStrategy} from "src/core/LendingStrategy.sol";

contract OnERC721ReceivedTest is BaseLendingStrategyTest {
    function testAddDebtAndSwap() public {
        vm.startPrank(borrower);
        safeTransferReceivedArgs.minOut = 1;
        uint160 priceLimit = _maxSqrtPriceLimit(true);
        safeTransferReceivedArgs.sqrtPriceLimitX96 = priceLimit;
        uint256 expectedOut = quoter.quoteExactInputSingle({
            tokenIn: address(strategy.perpetual()),
            tokenOut: address(underlying),
            fee: 10000,
            amountIn: debt,
            sqrtPriceLimitX96: priceLimit
        });
        nft.safeTransferFrom(borrower, address(strategy), collateralId, abi.encode(safeTransferReceivedArgs));
        ILendingStrategy.VaultInfo memory vaultInfo = strategy.vaultInfo(borrower, collateral.addr);
        assertEq(vaultInfo.count, 1);
        assertEq(vaultInfo.debt, debt);
        assertEq(expectedOut, underlying.balanceOf(borrower));
    }

    /// mainly a gas bench mark test
    function testAddDebtAndWhenNormStale() public {
        vm.warp(block.timestamp + 1 weeks);
        // update oracle timestamp
        oracleInfo = _getOracleInfoForCollateral(nft, underlying);
        safeTransferReceivedArgs.oracleInfo = oracleInfo;
        vm.startPrank(borrower);
        safeTransferReceivedArgs.minOut = 1;
        uint160 priceLimit = _maxSqrtPriceLimit(true);
        safeTransferReceivedArgs.sqrtPriceLimitX96 = priceLimit;
        uint256 expectedOut = quoter.quoteExactInputSingle({
            tokenIn: address(strategy.perpetual()),
            tokenOut: address(underlying),
            fee: 10000,
            amountIn: debt,
            sqrtPriceLimitX96: priceLimit
        });
        nft.safeTransferFrom(borrower, address(strategy), collateralId, abi.encode(safeTransferReceivedArgs));
        ILendingStrategy.VaultInfo memory vaultInfo = strategy.vaultInfo(borrower, collateral.addr);
        assertEq(vaultInfo.count, 1);
        assertEq(vaultInfo.debt, debt);
        assertEq(expectedOut, underlying.balanceOf(borrower));
    }
}
