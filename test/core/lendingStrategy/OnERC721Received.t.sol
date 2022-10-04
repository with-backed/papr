// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseLendingStrategyTest} from "test/core/lendingStrategy/BaseLendingStrategy.ft.sol";
import {ILendingStrategy} from "src/interfaces/ILendingStrategy.sol";
import {LendingStrategy} from "src/core/LendingStrategy.sol";

contract AddCollateralTest is BaseLendingStrategyTest {
    function testOpenVaultAddDebtAndSwap() public {
        vm.startPrank(borrower);
        uint256 nonce = 1;
        safeTransferReceivedArgs.vaultNonce = nonce;
        safeTransferReceivedArgs.minOut = 1;
        safeTransferReceivedArgs.mintDebtOrProceedsTo = address(strategy.pool());
        nft.safeTransferFrom(borrower, address(strategy), collateralId, abi.encode(safeTransferReceivedArgs));
    }

    function testOpenVaultAddDebtAndSwapLater() public {
        vm.warp(block.timestamp + 1 weeks);
        vm.startPrank(borrower);
        uint256 nonce = 1;
        safeTransferReceivedArgs.vaultNonce = nonce;
        safeTransferReceivedArgs.minOut = 1;
        safeTransferReceivedArgs.mintDebtOrProceedsTo = address(strategy.pool());
        nft.safeTransferFrom(borrower, address(strategy), collateralId, abi.encode(safeTransferReceivedArgs));
    }

    function testAddDebtToExistingVault() public {
        vm.startPrank(borrower);
        uint256 nonce = 1;
        safeTransferReceivedArgs.vaultNonce = nonce;
        nft.safeTransferFrom(borrower, address(strategy), collateralId, abi.encode(safeTransferReceivedArgs));
    }
}
