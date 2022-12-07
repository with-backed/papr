import "forge-std/Test.sol";
import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {PaprController} from "src/PaprController.sol";
import {IPaprController} from "src/interfaces/IPaprController.sol";
import {TestERC721} from "test/mocks/TestERC721.sol";
import {TestERC20} from "test/mocks/TestERC20.sol";
import {MainnetForking} from "test/base/MainnetForking.sol";
import {UniswapForking} from "test/base/UniswapForking.sol";

contract OwnerTest is MainnetForking, UniswapForking {
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

    function testSetPoolRevertsIfWrongToken0() public {
        IUniswapV3Factory factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
        address token0 = address(1);
        IUniswapV3Pool p = IUniswapV3Pool(factory.createPool(token0, controller.pool().token1(), 10000));
        vm.expectRevert(abi.encodeWithSelector(PaprController.WrongToken0.selector, token0, controller.pool().token0()));
        controller.setPool(p);
    }

    function testSetPoolRevertsIfWrongToken1() public {
        IUniswapV3Factory factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
        address token1 = address(type(uint160).max);
        IUniswapV3Pool p = IUniswapV3Pool(factory.createPool(controller.pool().token0(), token1, 10000));
        vm.expectRevert(abi.encodeWithSelector(PaprController.WrongToken1.selector, token1, controller.pool().token1()));
        controller.setPool(p);
    }

    function testSetPoolUpdatesPoolCorrectly() public {
        IUniswapV3Factory factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
        IUniswapV3Pool p =
            IUniswapV3Pool(factory.createPool(controller.pool().token0(), controller.pool().token1(), 3000));
        controller.setPool(p);
        assertEq(address(p), address(controller.pool()));
    }

    function testSetPoolRevertsIfNotOwner() public {
        vm.startPrank(address(1));
        vm.expectRevert("Ownable: caller is not the owner");
        controller.setPool(IUniswapV3Pool(address(1)));
    }
}
