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
        strategy.removeCollateral(borrower, collateral, oracleInfo);
        assertEq(nft.ownerOf(collateralId), borrower);
    }

    function testRemoveCollateralFailsIfWrongAddress() public {
        _addCollateral();
        vm.stopPrank();
        vm.expectRevert(ILendingStrategy.InvalidCollateralVaultIDCombination.selector);
        strategy.removeCollateral(borrower, collateral, oracleInfo);
    }

    function testRemoveCollateralFailsIfDoesNotExist() public {
        vm.expectRevert(ILendingStrategy.InvalidCollateralVaultIDCombination.selector);
        strategy.removeCollateral(borrower, collateral, oracleInfo);
    }

    function testRemoveCollateralFailsIfMaxDebtExceeded() public {
        _addCollateral();
        strategy.increaseDebt(borrower, collateral.addr, 1, oracleInfo);
        vm.expectRevert(abi.encodeWithSelector(ILendingStrategy.ExceedsMaxDebt.selector, 1, 0));
        strategy.removeCollateral(borrower, collateral, oracleInfo);
    }

    function testRemoveCollateralEmitsCorrectly() public {
        _addCollateral();
        vm.expectEmit(true, true, true, true);
        emit RemoveCollateral(borrower, collateral, 0);
        strategy.removeCollateral(borrower, collateral, oracleInfo);
    }

    function testRemoveCollateralUpdatesPricesCorrectly() public {
        _addCollateral();
        strategy.removeCollateral(borrower, collateral, _getOracleInfoForCollateral(collateral.addr, underlying));
        ILendingStrategy.VaultInfo memory vaultInfo = strategy.vaultInfo(borrower, collateral.addr);
        assertEq(0, vaultInfo.count);
    }

    function _addCollateral() internal {
        vm.startPrank(borrower);
        nft.approve(address(strategy), collateralId);
        strategy.addCollateral(collateral);
    }
}
