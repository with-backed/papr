// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.17;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";

import {BasePaprControllerTest} from "test/paprController/BasePaprController.ft.sol";
import {PaprController} from "src/PaprController.sol";
import {IPaprController} from "src/interfaces/IPaprController.sol";
import {ReservoirOracleUnderwriter} from "src/ReservoirOracleUnderwriter.sol";
import {TestERC721} from "test/mocks/TestERC721.sol";

contract AddCollateralTest is BasePaprControllerTest {
    event AddCollateral(address indexed account, ERC721 indexed collateralAddress, uint256 indexed tokenId);

    function testAddCollateralUpdatesCollateralOwnerCorrectly() public {
        _addCollateral();
        assertEq(controller.collateralOwner(collateral.addr, collateral.id), borrower);
    }

    function testAddCollateralEmitsAddCollateral() public {
        vm.startPrank(borrower);
        nft.approve(address(controller), collateralId);
        IPaprController.Collateral[] memory c = new IPaprController.Collateral[](1);
        c[0] = collateral;
        vm.expectEmit(true, true, true, false);
        emit AddCollateral(borrower, collateral.addr, collateral.id);
        controller.addCollateral(c);
    }

    function testAddCollateralIncreasesCountInVault() public {
        uint256 beforeCount = controller.vaultInfo(borrower, collateral.addr).count;
        _addCollateral();
        assertEq(beforeCount + 1, controller.vaultInfo(borrower, collateral.addr).count);
    }

    function testAddCollateralFailsIfInvalidCollateral() public {
        TestERC721 invalidNFT = new TestERC721();
        vm.startPrank(borrower);
        nft.approve(address(controller), collateralId);
        vm.expectRevert(IPaprController.InvalidCollateral.selector);
        IPaprController.Collateral[] memory c = new IPaprController.Collateral[](1);
        c[0] = IPaprController.Collateral(ERC721(address(1)), 1);
        controller.addCollateral(c);
    }

    function _addCollateral() internal {
        vm.startPrank(borrower);
        nft.approve(address(controller), collateralId);
        IPaprController.Collateral[] memory c = new IPaprController.Collateral[](1);
        c[0] = collateral;
        controller.addCollateral(c);
    }
}
