// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.17;

import {BasePaprControllerTest, TestERC721} from "test/paprController/BasePaprController.ft.sol";
import {IPaprController, ERC721} from "src/interfaces/IPaprController.sol";
import {PaprController} from "src/PaprController.sol";
import {ReservoirOracleUnderwriter} from "src/ReservoirOracleUnderwriter.sol";

contract RemoveCollateralTest is BasePaprControllerTest {
    event RemoveCollateral(address indexed account, ERC721 indexed collateralAddress, uint256 indexed tokenId);

    IPaprController.Collateral[] collateralArr;

    function setUp() public override {
        super.setUp();
        collateralArr.push(collateral);
    }

    function testRemoveCollateralSendsCorrectly() public {
        _addCollateral();
        _removeCollateral();
        assertEq(nft.ownerOf(collateralId), borrower);
    }

    function testRemoveCollateralUpdatesCollateralOwnerCorrectly() public {
        _addCollateral();
        _removeCollateral();
        assertEq(controller.collateralOwner(collateral.addr, collateral.id), address(0));
    }

    function testRemoveCollateralDecreasesVaultCount() public {
        _addCollateral();
        uint256 beforeCount = controller.vaultInfo(borrower, collateral.addr).count;
        _removeCollateral();
        assertEq(beforeCount - 1, controller.vaultInfo(borrower, collateral.addr).count);
    }

    function testRemoveCollateralFailsIfCallerIsNotOwner() public {
        _addCollateral();
        vm.stopPrank();
        vm.expectRevert(IPaprController.OnlyCollateralOwner.selector);
        controller.removeCollateral(borrower, collateralArr, oracleInfo);
    }

    function testRemoveCollateralFailsIfDoesNotExist() public {
        vm.expectRevert(IPaprController.OnlyCollateralOwner.selector);
        controller.removeCollateral(borrower, collateralArr, oracleInfo);
    }

    function testRemoveCollateralFailsIfMaxDebtExceeded() public {
        _addCollateral();
        controller.increaseDebt(borrower, collateral.addr, 1, oracleInfo);
        vm.expectRevert(abi.encodeWithSelector(IPaprController.ExceedsMaxDebt.selector, 1, 0));
        controller.removeCollateral(borrower, collateralArr, oracleInfo);
    }

    function testRemoveCollateralFailsIfWrongOraclePriceType() public {
        _addCollateral();
        controller.increaseDebt(borrower, collateral.addr, 1, oracleInfo);

        priceKind = ReservoirOracleUnderwriter.PriceKind.TWAP;
        oracleInfo = _getOracleInfoForCollateral(collateral.addr, underlying);
        vm.expectRevert(abi.encodeWithSelector(ReservoirOracleUnderwriter.WrongIdentifierFromOracleMessage.selector));
        controller.removeCollateral(borrower, collateralArr, oracleInfo);
    }

    function testRemoveCollateralEmitsCorrectly() public {
        _addCollateral();
        vm.expectEmit(true, true, false, false);
        emit RemoveCollateral(borrower, collateral.addr, collateral.id);
        controller.removeCollateral(borrower, collateralArr, oracleInfo);
    }

    function testRemoveCollateralFailsIfDifferentCollateralAddresses() public {
        _addCollateral();
        ERC721 newCollateral = new TestERC721();
        IPaprController.Collateral[] memory collateralArrLocal = new IPaprController.Collateral[](2);
        collateralArrLocal[0] = collateral;
        collateralArrLocal[1] = IPaprController.Collateral({addr: ERC721(address(1)), id: 1});
        vm.expectRevert(IPaprController.CollateralAddressesDoNotMatch.selector);
        controller.removeCollateral(borrower, collateralArrLocal, oracleInfo);
    }

    function testRemoveCollateralWorksIfSameAddress() public {
        nft.mint(borrower, 5);
        collateralArr.push(IPaprController.Collateral({addr: nft, id: 5}));
        _addCollateral();
        assertEq(controller.collateralOwner(collateral.addr, collateral.id), borrower);
        assertEq(controller.collateralOwner(collateral.addr, 5), borrower);
        _removeCollateral();
        assertEq(controller.collateralOwner(collateral.addr, collateral.id), address(0));
        assertEq(controller.collateralOwner(collateral.addr, 5), address(0));
    }

    function _addCollateral() internal {
        vm.startPrank(borrower);
        for (uint256 i = 0; i < collateralArr.length; i++) {
            nft.approve(address(controller), collateralArr[i].id);
        }
        controller.addCollateral(collateralArr);
    }

    function _removeCollateral() internal {
        controller.removeCollateral(borrower, collateralArr, oracleInfo);
    }
}
