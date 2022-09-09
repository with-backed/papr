// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseLendingStrategyTest} from
    "test/core/lendingStrategy/BaseLendingStrategy.ft.sol";
import {ILendingStrategy} from "src/interfaces/ILendingStrategy.sol";
import {LendingStrategy} from "src/core/LendingStrategy.sol";

contract RemoveCollateralTest is BaseLendingStrategyTest {
    ILendingStrategy.Collateral collateral;

    event RemoveCollateral(
        uint256 indexed vaultId,
        ILendingStrategy.Collateral collateral,
        uint256 vaultDebt
    );

    function testRemoveCollateralSendsCorrectly() public {
        _addCollateral();
        strategy.removeCollateral(address(1), vaultNonce, collateral);
        assertEq(nft.ownerOf(collateralId), address(1));
    }

    function testRemoveCollateralFailsIfWrongAddress() public {
        _addCollateral();
        vm.stopPrank();
        vm.expectRevert(
            LendingStrategy.InvalidCollateralVaultIDCombination.selector
        );
        strategy.removeCollateral(address(1), vaultNonce, collateral);
    }

    function testRemoveCollateralFailsIfDoesNotExist() public {
        vm.expectRevert(
            LendingStrategy.InvalidCollateralVaultIDCombination.selector
        );
        strategy.removeCollateral(address(1), vaultNonce, collateral);
    }

    function testRemoveCollateralFailsIfMaxDebtExceeded() public {
        _addCollateral();
        strategy.increaseDebt(vaultId, vaultNonce, address(1), 1);
        vm.expectRevert(
            abi.encodeWithSelector(LendingStrategy.ExceedsMaxDebt.selector, 1, 0)
        );
        strategy.removeCollateral(address(1), vaultNonce, collateral);
    }

    function testRemoveCollateralEmitsCorrectly() public {
        _addCollateral();
        vm.expectEmit(true, true, true, true);
        emit RemoveCollateral(vaultId, collateral, 0);
        strategy.removeCollateral(address(1), vaultNonce, collateral);
    }

    function testRemoveCollateralUpdatesPricesCorrectly() public {
        _addCollateral();
        strategy.removeCollateral(address(1), vaultNonce, collateral);
        assertEq(
            0,
            strategy.collateralFrozenOraclePrice(
                strategy.collateralHash(collateral, vaultId)
            )
        );
        (, uint128 collateralValue) = strategy.vaultInfo(vaultId);
        assertEq(0, collateralValue);
    }

    function _addCollateral() internal {
        vaultId = strategy.vaultIdentifier(vaultNonce, borrower);
        collateral = ILendingStrategy.Collateral(nft, collateralId);
        vm.startPrank(borrower);
        nft.approve(address(strategy), collateralId);
        strategy.addCollateral(vaultId, collateral, oracleInfo, sig);
    }
}
