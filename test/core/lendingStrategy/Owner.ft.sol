import "forge-std/Test.sol";

import {LendingStrategy} from "src/core/LendingStrategy.sol";
import {ILendingStrategy} from "src/interfaces/ILendingStrategy.sol";
import {TestERC721} from "test/mocks/TestERC721.sol";
import {TestERC20} from "test/mocks/TestERC20.sol";
import {MainnetForking} from "test/base/MainnetForking.sol";
import {UniswapForking} from "test/base/UniswapForking.sol";

contract OwnerTest is MainnetForking, UniswapForking {
    TestERC721 nft = new TestERC721();
    TestERC20 underlying = new TestERC20();
    LendingStrategy strategy;

    function setUp() public {
        strategy = new LendingStrategy("PUNKs Loans", "PL", 0.1e18, 2e18, 0.8e18, underlying);
    }

    function testSetAllowedCollateralFailsIfNotOwner() public {
        ILendingStrategy.SetAllowedCollateralArg[] memory args = new ILendingStrategy.SetAllowedCollateralArg[](1);
        args[0] = ILendingStrategy.SetAllowedCollateralArg(address(nft), true);

        vm.startPrank(address(1));
        vm.expectRevert("Ownable: caller is not the owner");
        strategy.setAllowedCollateral(args);
    }

    function testSetAllowedCollateralWorksIfOwner() public {
        ILendingStrategy.SetAllowedCollateralArg[] memory args = new ILendingStrategy.SetAllowedCollateralArg[](1);
        args[0] = ILendingStrategy.SetAllowedCollateralArg(address(nft), true);

        strategy.setAllowedCollateral(args);

        assertTrue(strategy.isAllowed(address(nft)));
    }
}
