// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseLendingStrategyTest} from "test/core/lendingStrategy/BaseLendingStrategy.ft.sol";
import {ILendingStrategy} from "src/interfaces/ILendingStrategy.sol";
import {LendingStrategy} from "src/core/LendingStrategy.sol";

contract RemoveCollateralTest is BaseLendingStrategyTest {
    event RemoveCollateral(
        address indexed account, ILendingStrategy.Collateral collateral, uint256 vaultCollateralValue
    );

    function testRemoveCollateralSendsCorrectly() public {
        _addCollateral();
        strategy.removeCollateral(address(1), collateral);
        assertEq(nft.ownerOf(collateralId), address(1));
    }

    function testRemoveCollateralFailsIfWrongAddress() public {
        _addCollateral();
        vm.stopPrank();
        vm.expectRevert(ILendingStrategy.InvalidCollateralVaultIDCombination.selector);
        strategy.removeCollateral(address(1), collateral);
    }

    function testRemoveCollateralFailsIfDoesNotExist() public {
        vm.expectRevert(ILendingStrategy.InvalidCollateralVaultIDCombination.selector);
        strategy.removeCollateral(address(1), collateral);
    }

    function testRemoveCollateralFailsIfMaxDebtExceeded() public {
        _addCollateral();
        strategy.increaseDebt(address(1), 1);
        vm.expectRevert(abi.encodeWithSelector(ILendingStrategy.ExceedsMaxDebt.selector, 1, 0));
        strategy.removeCollateral(address(1), collateral);
    }

    function testRemoveCollateralEmitsCorrectly() public {
        _addCollateral();
        vm.expectEmit(true, true, true, true);
        emit RemoveCollateral(borrower, collateral, 0);
        strategy.removeCollateral(address(1), collateral);
    }

    function testRemoveCollateralUpdatesPricesCorrectly() public {
        _addCollateral();
        strategy.removeCollateral(address(1), collateral);
        assertEq(0, strategy.collateralFrozenOraclePrice(strategy.collateralHash(collateral, borrower)));
        ILendingStrategy.VaultInfo memory vaultInfo = strategy.vaultInfo(borrower);
        assertEq(0, vaultInfo.collateralValue);
    }

    function _addCollateral() internal {
        vm.startPrank(borrower);
        nft.approve(address(strategy), collateralId);
        strategy.addCollateral(collateral, oracleInfo);
    }
}
