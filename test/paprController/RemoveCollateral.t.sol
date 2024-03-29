// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.17;

import {ERC721TokenReceiver} from "solmate/tokens/ERC721.sol";

import {BasePaprControllerTest, TestERC721} from "./BasePaprController.ft.sol";
import {IPaprController, ERC721} from "../../src/interfaces/IPaprController.sol";
import {PaprController} from "../../src/PaprController.sol";
import {ReservoirOracleUnderwriter} from "../../src/ReservoirOracleUnderwriter.sol";

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

    function testRemoveCollateralFailsIfMaxDebtEqual() public {
        nft.mint(borrower, 2);
        collateralArr.push(IPaprController.Collateral({addr: nft, id: 2}));
        _addCollateral();
        uint256 maxForOne = controller.maxDebt(oraclePrice);
        controller.increaseDebt(borrower, collateral.addr, maxForOne, oracleInfo);
        vm.expectRevert(abi.encodeWithSelector(IPaprController.ExceedsMaxDebt.selector, maxForOne, maxForOne));
        controller.removeCollateral(borrower, collateralArr, oracleInfo);
    }

    function testRemoveCollateralWithReentryPayDebtFails() public {
        _addCollateral();
        controller.increaseDebt(address(this), collateral.addr, 1, oracleInfo);
        vm.expectRevert(abi.encodeWithSelector(IPaprController.ExceedsMaxDebt.selector, 1, 0));
        controller.removeCollateral(address(this), collateralArr, oracleInfo);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4) {
        controller.reduceDebt(borrower, collateral.addr, 1);
        return ERC721TokenReceiver.onERC721Received.selector;
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

    function testRevertsIfDebtExeedsMaxPrice() public {
        nft.mint(borrower, 5);
        collateralArr.push(IPaprController.Collateral({addr: nft, id: 5}));
        _addCollateral();
        // uint256 originalPrice = oraclePrice;
        debt = controller.maxDebt(oraclePrice * 2) - 1;
        // cache
        controller.increaseDebt(borrower, collateral.addr, debt, oracleInfo);
        (, uint216 p) = controller.cachedPriceForAsset(collateral.addr);

        uint256 passedTime = 1 days;
        vm.warp(block.timestamp + passedTime);
        uint256 maxPerSecond = 0.5e18 / uint256(1 days);
        uint256 max = p * ((maxPerSecond * passedTime) + 1e18) / 1e18;
        oraclePrice = max * 2;
        oracleInfo = _getOracleInfoForCollateral(collateral.addr, controller.underlying());
        uint256 maxPapr = controller.maxDebt(max);
        IPaprController.Collateral[] memory arr = new IPaprController.Collateral[](1);
        arr[0] = collateral;
        vm.expectRevert(abi.encodeWithSelector(IPaprController.ExceedsMaxDebt.selector, debt, maxPapr));
        controller.removeCollateral(borrower, arr, oracleInfo);
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
