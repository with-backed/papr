// SPDX-License-Identifier: GPL-2.0-or-later

import "forge-std/Test.sol";
import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {PaprController} from "../../src/PaprController.sol";
import {IPaprController} from "../../src/interfaces/IPaprController.sol";
import {PaprToken} from "../../src/PaprToken.sol";
import {TestERC721, ERC721} from "../mocks/TestERC721.sol";
import {TestERC20} from "../mocks/TestERC20.sol";
import {MainnetForking} from "../base/MainnetForking.sol";
import {UniswapForking} from "../base/UniswapForking.sol";

contract OwnerFunctionsTest is MainnetForking, UniswapForking {
    event AllowCollateral(ERC721 indexed collateral, bool isAllowed);
    event UpdateFundingPeriod(uint256 newPeriod);
    event UpdatePool(address indexed newPool);
    event UpdateLiquidationsLocked(bool locked);
    event ProposeAllowedCollateral(ERC721 indexed asset);
    event CancelProposedAllowedCollateral(ERC721 indexed asset);

    TestERC721 nft = new TestERC721();
    TestERC20 underlying = new TestERC20();
    PaprController controller;

    function setUp() public {
        ERC721[] memory collateralArr = new ERC721[](1);
        collateralArr[0] = nft;

        controller = new PaprController(
            "PUNKs Loans",
            "PL",
            0.1e18,
            2e18,
            0.8e18,
            underlying,
            address(1),
            collateralArr
        );
    }

    function testRevertsIfNotOwner() public {
        bytes[] memory calls = new bytes[](5);
        calls[0] = abi.encodeWithSelector(controller.proposeAllowedCollateral.selector, nft);
        calls[1] = abi.encodeWithSelector(controller.cancelProposedCollateral.selector, nft);
        ERC721[] memory assets = new ERC721[](1);
        assets[0] = nft;
        calls[2] = abi.encodeWithSelector(controller.removeAllowedCollateral.selector, assets);
        calls[3] = abi.encodeWithSelector(controller.setFundingPeriod.selector, 1);
        calls[4] = abi.encodeWithSelector(controller.setPool.selector, address(2));

        vm.startPrank(address(1));
        for (uint256 i; i < calls.length; i++) {
            (bool success, bytes memory data) = address(controller).call(calls[i]);
            assertFalse(success);
            bytes memory n = new bytes(data.length - 68);
            for (uint256 j = 68; j < data.length; j++) {
                n[j - 68] = data[j];
            }
            assertEq("Ownable: caller is not the owner", string(n));
        }
    }

    function testProposeAllowedCollateralSetsProposedTimestamp() public {
        assertEq(controller.proposedTimestamp(nft), 0);
        controller.proposeAllowedCollateral(nft);

        assertEq(controller.proposedTimestamp(nft), block.timestamp);
    }

    function testProposeAllowedCollateralEmitsCorrectly() public {
        vm.expectEmit(true, false, false, false);
        emit ProposeAllowedCollateral(nft);
        controller.proposeAllowedCollateral(nft);
    }

    function testCancelProposedCollateralDeletesTimestamp() public {
        assertEq(controller.proposedTimestamp(nft), 0);
        controller.proposeAllowedCollateral(nft);
        assertEq(controller.proposedTimestamp(nft), block.timestamp);

        controller.cancelProposedCollateral(nft);
        assertEq(controller.proposedTimestamp(nft), 0);
    }

    function testCancelProposedCollateralEmitsCorrectly() public {
        vm.expectEmit(true, false, false, false);
        emit CancelProposedAllowedCollateral(nft);
        controller.cancelProposedCollateral(nft);
    }

    function testRemoveCollateralSetsAllowedToFalse() public {
        assertTrue(controller.isAllowed(nft));
        ERC721[] memory assets = new ERC721[](1);
        assets[0] = nft;
        controller.removeAllowedCollateral(assets);
        assertFalse(controller.isAllowed(nft));
    }

    function testRemoveCollateralEmitsCorrectly() public {
        ERC721[] memory assets = new ERC721[](1);
        assets[0] = nft;
        vm.expectEmit(true, false, false, true);
        emit AllowCollateral(nft, false);
        controller.removeAllowedCollateral(assets);
    }

    // not an owner function but easier to test here

    function testAcceptProposedCollateralRevertsIfNotProposed() public {
        vm.expectRevert(IPaprController.AssetNotProposed.selector);
        controller.acceptProposedCollateral(nft);
    }

    function testAcceptProposedCollateralRevertsIfTooSoon() public {
        controller.proposeAllowedCollateral(nft);
        vm.expectRevert(IPaprController.ProposalPeriodNotComplete.selector);
        vm.warp(block.timestamp + 5 days - 1);
        controller.acceptProposedCollateral(nft);
    }

    function testAcceptProposedCollateralSetsIsAllowedToTrue() public {
        ERC721 newCollateral = ERC721(address(2));
        assertFalse(controller.isAllowed(newCollateral));
        controller.proposeAllowedCollateral(newCollateral);
        vm.warp(block.timestamp + 5 days);
        // doesn't have to be owner
        vm.prank(address(3));
        controller.acceptProposedCollateral(newCollateral);
        assertTrue(controller.isAllowed(newCollateral));
    }

    function testAcceptProposedCollateralEmitsCorrectly() public {
        ERC721 newCollateral = ERC721(address(2));
        controller.proposeAllowedCollateral(newCollateral);
        vm.warp(block.timestamp + 5 days);
        vm.expectEmit(true, false, false, true);
        emit AllowCollateral(newCollateral, true);
        controller.acceptProposedCollateral(newCollateral);
    }

    function testSetPoolEmitsCorrectly() public {
        address p = factory.createPool(address(underlying), address(controller.papr()), 3000);
        vm.expectEmit(true, false, false, false);
        emit UpdatePool(p);
        controller.setPool(p);
    }

    function testSetPoolRevertsIfNotOwner() public {
        vm.startPrank(address(1));
        vm.expectRevert("Ownable: caller is not the owner");
        controller.setPool(address(1));
    }

    function testSetFundingPeriodEmitsCorrectly() public {
        vm.expectEmit(false, false, false, true);
        emit UpdateFundingPeriod(90 days);
        controller.setFundingPeriod(90 days);
    }

    function testSetFundingPeriodRevertsIfNotOwner() public {
        vm.startPrank(address(1));
        vm.expectRevert("Ownable: caller is not the owner");
        controller.setFundingPeriod(1);
    }

    function testSetLiquidationsLockedUpdatesLiquidationsLocked() public {
        vm.expectEmit(false, false, false, true);
        emit UpdateLiquidationsLocked(true);
        controller.setLiquidationsLocked(true);
        assertTrue(controller.liquidationsLocked());
    }

    function testSetLiquidationsLockedRevertsIfCallerNotOwner() public {
        vm.startPrank(address(1));
        vm.expectRevert("Ownable: caller is not the owner");
        controller.setLiquidationsLocked(false);
    }
}
