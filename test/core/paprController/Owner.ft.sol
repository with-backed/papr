import "forge-std/Test.sol";

import {PaprController} from "src/core/PaprController.sol";
import {IPaprController} from "src/interfaces/IPaprController.sol";
import {TestERC721} from "test/mocks/TestERC721.sol";
import {TestERC20} from "test/mocks/TestERC20.sol";
import {MainnetForking} from "test/base/MainnetForking.sol";
import {UniswapForking} from "test/base/UniswapForking.sol";

contract OwnerTest is MainnetForking, UniswapForking {
    TestERC721 nft = new TestERC721();
    TestERC20 underlying = new TestERC20();
    PaprController strategy;

    function setUp() public {
        strategy = new PaprController("PUNKs Loans", "PL", 0.1e18, 2e18, 0.8e18, underlying, address(1));
    }

    function testSetAllowedCollateralFailsIfNotOwner() public {
        IPaprController.CollateralAllowedConfig[] memory args = new IPaprController.CollateralAllowedConfig[](1);
        args[0] = IPaprController.CollateralAllowedConfig(address(nft), true);

        vm.startPrank(address(1));
        vm.expectRevert("Ownable: caller is not the owner");
        strategy.setAllowedCollateral(args);
    }

    function testSetAllowedCollateralWorksIfOwner() public {
        IPaprController.CollateralAllowedConfig[] memory args = new IPaprController.CollateralAllowedConfig[](1);
        args[0] = IPaprController.CollateralAllowedConfig(address(nft), true);

        strategy.setAllowedCollateral(args);

        assertTrue(strategy.isAllowed(address(nft)));
    }
}
