// SPDX-License-Identifier: GPL-2.0-or-later

import "forge-std/Test.sol";
import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {PaprController} from "../../src/PaprController.sol";
import {IPaprController} from "../../src/interfaces/IPaprController.sol";
import {PaprToken} from "../../src/PaprToken.sol";
import {TestERC721} from "../mocks/TestERC721.sol";
import {TestERC20} from "../mocks/TestERC20.sol";
import {MainnetForking} from "../base/MainnetForking.sol";
import {UniswapForking} from "../base/UniswapForking.sol";

contract OwnerFunctionsTest is MainnetForking, UniswapForking {
    TestERC721 nft = new TestERC721();
    TestERC20 underlying = new TestERC20();
    PaprController controller;

    function setUp() public {
        controller = new PaprController("PUNKs Loans", "PL", 0.1e18, 2e18, 0.8e18, underlying, address(1));
    }

    function testSetAllowedCollateralFailsIfNotOwner() public {
        IPaprController.CollateralAllowedConfig[] memory args = new IPaprController.CollateralAllowedConfig[](1);
        args[0] = IPaprController.CollateralAllowedConfig(address(nft), true);

        vm.startPrank(address(1));
        vm.expectRevert("Ownable: caller is not the owner");
        controller.setAllowedCollateral(args);
    }

    function testSetAllowedCollateralRevertsIfCollateralZeroAddress() public {
        IPaprController.CollateralAllowedConfig[] memory args = new IPaprController.CollateralAllowedConfig[](1);
        args[0] = IPaprController.CollateralAllowedConfig(address(0), true);

        vm.expectRevert(IPaprController.InvalidCollateral.selector);
        controller.setAllowedCollateral(args);
    }

    function testSetAllowedCollateralWorksIfOwner() public {
        IPaprController.CollateralAllowedConfig[] memory args = new IPaprController.CollateralAllowedConfig[](1);
        args[0] = IPaprController.CollateralAllowedConfig(address(nft), true);

        controller.setAllowedCollateral(args);

        assertTrue(controller.isAllowed(address(nft)));
    }

    function testSetPoolRevertsIfNotOwner() public {
        vm.startPrank(address(1));
        vm.expectRevert("Ownable: caller is not the owner");
        controller.setPool(address(1));
    }

    function testSetFundingPeriodRevertsIfNotOwner() public {
        vm.startPrank(address(1));
        vm.expectRevert("Ownable: caller is not the owner");
        controller.setFundingPeriod(1);
    }

    function testSendPaprFromAuctionFeesWorksIfOwner() public {
        PaprToken paprToken = PaprToken(address(controller.papr()));

        vm.startPrank(address(controller));
        paprToken.mint(address(controller), 1e18);
        paprToken.approve(address(controller), 1e18);
        vm.stopPrank();

        assertEq(paprToken.balanceOf(address(controller)), 1e18);

        controller.sendPaprFromAuctionFees(address(1), 1e18);
        assertEq(paprToken.balanceOf(address(controller)), 0);
        assertEq(paprToken.balanceOf(address(1)), 1e18);
    }

    function testSendPaprFromAuctionFeesRevertsIfNotOwner() public {
        PaprToken paprToken = PaprToken(address(controller.papr()));

        vm.startPrank(address(controller));
        paprToken.mint(address(controller), 1e18);
        paprToken.approve(address(controller), 1e18);
        vm.stopPrank();

        vm.startPrank(address(1));
        vm.expectRevert("Ownable: caller is not the owner");
        controller.sendPaprFromAuctionFees(address(1), 1e18);
    }

    function testBurnPaprFromAuctionFeesWorksIfOwner() public {
        PaprToken paprToken = PaprToken(address(controller.papr()));

        vm.startPrank(address(controller));
        paprToken.mint(address(controller), 1e18);
        paprToken.approve(address(controller), 1e18);
        vm.stopPrank();

        assertEq(paprToken.balanceOf(address(controller)), 1e18);
        assertEq(paprToken.totalSupply(), 1e18);

        controller.burnPaprFromAuctionFees(1e18);
        assertEq(paprToken.balanceOf(address(controller)), 0);
        assertEq(paprToken.totalSupply(), 0);
    }

    function testBurnPaprFromAuctionFeesRevertsIfNotOwner() public {
        vm.startPrank(address(1));
        vm.expectRevert("Ownable: caller is not the owner");
        controller.burnPaprFromAuctionFees(1e18);
    }

    function testSetLiquidationsLockedUpdatesLiquidationsLocked() public {
        controller.setLiquidationsLocked(true);
        assertTrue(controller.liquidationsLocked());
    }

    function testSetLiquidationsLockedRevertsIfCallerNotOwner() public {
        vm.startPrank(address(1));
        vm.expectRevert("Ownable: caller is not the owner");
        controller.setLiquidationsLocked(false);
    }
}
