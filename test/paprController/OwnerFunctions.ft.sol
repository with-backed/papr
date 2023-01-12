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
    event AllowCollateral(address indexed collateral, bool isAllowed);
    event UpdateFundingPeriod(uint256 newPeriod);
    event UpdatePool(address indexed newPool);
    event UpdateLiquidationsLocked(bool locked);

    TestERC721 nft = new TestERC721();
    TestERC20 underlying = new TestERC20();
    PaprController controller;

    function setUp() public {
        controller = new PaprController(
            "PUNKs Loans",
            "PL",
            0.1e18,
            2e18,
            0.8e18,
            underlying,
            address(1)
        );
    }

    function testSetAllowedCollateralFailsIfNotOwner() public {
        IPaprController.CollateralAllowedConfig[] memory args = new IPaprController.CollateralAllowedConfig[](1);
        args[0] = IPaprController.CollateralAllowedConfig(nft, true);

        vm.startPrank(address(1));
        vm.expectRevert("Ownable: caller is not the owner");
        controller.setAllowedCollateral(args);
    }

    function testSetAllowedCollateralRevertsIfCollateralZeroAddress() public {
        IPaprController.CollateralAllowedConfig[] memory args = new IPaprController.CollateralAllowedConfig[](1);
        args[0] = IPaprController.CollateralAllowedConfig(TestERC721(address(0)), true);

        vm.expectRevert(IPaprController.InvalidCollateral.selector);
        controller.setAllowedCollateral(args);
    }

    function testSetAllowedCollateralWorksIfOwner() public {
        IPaprController.CollateralAllowedConfig[] memory args = new IPaprController.CollateralAllowedConfig[](1);
        args[0] = IPaprController.CollateralAllowedConfig(nft, true);

        vm.expectEmit(true, false, false, true);
        emit AllowCollateral(address(nft), true);
        controller.setAllowedCollateral(args);

        assertTrue(controller.isAllowed(nft));
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
