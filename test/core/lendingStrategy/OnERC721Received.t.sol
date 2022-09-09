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
        safeTransferReceivedArgs.vaultId =
            strategy.vaultIdentifier(nonce, borrower);
        safeTransferReceivedArgs.minOut = 1;
        safeTransferReceivedArgs.mintDebtOrProceedsTo = address(strategy.pool());
        nft.safeTransferFrom(
            borrower,
            address(strategy),
            collateralId,
            abi.encode(safeTransferReceivedArgs)
        );
    }

    function testAddDebtToExistingVault() public {
        vm.startPrank(borrower);
        uint256 nonce = 1;
        safeTransferReceivedArgs.vaultId =
            strategy.vaultIdentifier(nonce, borrower);
        safeTransferReceivedArgs.vaultNonce = nonce;
        nft.safeTransferFrom(
            borrower,
            address(strategy),
            collateralId,
            abi.encode(safeTransferReceivedArgs)
        );
    }

    function testAddDebtToExistingVaultRevertsIfNotVaultOwner() public {
        vm.startPrank(borrower);
        safeTransferReceivedArgs.vaultId = 1;
        vm.expectRevert(LendingStrategy.OnlyVaultOwner.selector);
        nft.safeTransferFrom(
            borrower,
            address(strategy),
            collateralId,
            abi.encode(safeTransferReceivedArgs)
        );
    }
}