// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BasePaprControllerTest} from "test/paprController/BasePaprController.ft.sol";
import {IPaprController} from "src/interfaces/IPaprController.sol";
import {PaprController} from "src/PaprController.sol";

contract RemoveCollateralTest is BasePaprControllerTest {
    event RemoveCollateral(address indexed account, IPaprController.Collateral collateral);

    function testRemoveCollateralSendsCorrectly() public {
        _addCollateral();
        controller.removeCollateral(borrower, collateral, oracleInfo);
        assertEq(nft.ownerOf(collateralId), borrower);
    }

    function testRemoveCollateralFailsIfWrongAddress() public {
        _addCollateral();
        vm.stopPrank();
        vm.expectRevert(IPaprController.OnlyCollateralOwner.selector);
        controller.removeCollateral(borrower, collateral, oracleInfo);
    }

    function testRemoveCollateralFailsIfDoesNotExist() public {
        vm.expectRevert(IPaprController.OnlyCollateralOwner.selector);
        controller.removeCollateral(borrower, collateral, oracleInfo);
    }

    function testRemoveCollateralFailsIfMaxDebtExceeded() public {
        _addCollateral();
        controller.increaseDebt(borrower, collateral.addr, 1, oracleInfo);
        vm.expectRevert(abi.encodeWithSelector(IPaprController.ExceedsMaxDebt.selector, 1, 0));
        controller.removeCollateral(borrower, collateral, oracleInfo);
    }

    function testRemoveCollateralEmitsCorrectly() public {
        _addCollateral();
        vm.expectEmit(true, true, false, false);
        emit RemoveCollateral(borrower, collateral);
        controller.removeCollateral(borrower, collateral, oracleInfo);
    }

    function testRemoveCollateralUpdatesPricesCorrectly() public {
        _addCollateral();
        controller.removeCollateral(borrower, collateral, _getOracleInfoForCollateral(collateral.addr, underlying));
        IPaprController.VaultInfo memory vaultInfo = controller.vaultInfo(borrower, collateral.addr);
        assertEq(0, vaultInfo.count);
    }

    function _addCollateral() internal {
        vm.startPrank(borrower);
        nft.approve(address(controller), collateralId);
        controller.addCollateral(collateral);
    }
}
