// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.17;

import {BasePaprControllerTest} from "./BasePaprController.ft.sol";
import {IPaprController} from "../../src/interfaces/IPaprController.sol";
import {PaprController} from "../../src/PaprController.sol";

contract OnERC721ReceivedTest is BasePaprControllerTest {
    function testAddDebtAndSwap() public {
        vm.startPrank(borrower);
        safeTransferReceivedArgs.swapParams.minOut = 1;
        uint160 priceLimit = _maxSqrtPriceLimit(true);
        safeTransferReceivedArgs.swapParams.sqrtPriceLimitX96 = priceLimit;
        uint256 expectedOut = quoter.quoteExactInputSingle({
            tokenIn: address(controller.papr()),
            tokenOut: address(underlying),
            fee: 10000,
            amountIn: debt,
            sqrtPriceLimitX96: priceLimit
        });
        nft.safeTransferFrom(borrower, address(controller), collateralId, abi.encode(safeTransferReceivedArgs));
        IPaprController.VaultInfo memory vaultInfo = controller.vaultInfo(borrower, collateral.addr);
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
        safeTransferReceivedArgs.swapParams.minOut = 1;
        uint160 priceLimit = _maxSqrtPriceLimit(true);
        safeTransferReceivedArgs.swapParams.sqrtPriceLimitX96 = priceLimit;
        uint256 expectedOut = quoter.quoteExactInputSingle({
            tokenIn: address(controller.papr()),
            tokenOut: address(underlying),
            fee: 10000,
            amountIn: debt,
            sqrtPriceLimitX96: priceLimit
        });
        nft.safeTransferFrom(borrower, address(controller), collateralId, abi.encode(safeTransferReceivedArgs));
        IPaprController.VaultInfo memory vaultInfo = controller.vaultInfo(borrower, collateral.addr);
        assertEq(vaultInfo.count, 1);
        assertEq(vaultInfo.debt, debt);
        assertEq(expectedOut, underlying.balanceOf(borrower));
    }
}
