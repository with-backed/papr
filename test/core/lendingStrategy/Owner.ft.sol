import "forge-std/Test.sol";

import {LendingStrategy} from "src/core/LendingStrategy.sol";
import {ILendingStrategy} from "src/interfaces/ILendingStrategy.sol";
import {StrategyFactory} from "src/core/StrategyFactory.sol";
import {TestERC721} from "test/mocks/TestERC721.sol";
import {TestERC20} from "test/mocks/TestERC20.sol";
import {MainnetForking} from "test/base/MainnetForking.sol";
import {UniswapForking} from "test/base/UniswapForking.sol";

contract OwnerTest is MainnetForking, UniswapForking {
    TestERC721 nft = new TestERC721();
    TestERC20 underlying = new TestERC20();
    LendingStrategy strategy;

    function setUp() public {
        StrategyFactory factory = new StrategyFactory();
        strategy = factory.newStrategy("PUNKs Loans", "PL", "ipfs-link", 0.1e18, 0.5e18, underlying);
    }

    function testSetAllowedCollateralFailsIfNotOwner() public {
        ILendingStrategy.SetAllowedCollateralArg[] memory args = new ILendingStrategy.SetAllowedCollateralArg[](1);
        args[0] = ILendingStrategy.SetAllowedCollateralArg(address(nft), true);

        vm.expectRevert("Ownable: caller is not the owner");
        strategy.setAllowedCollateral(args);
    }

    function testSetAllowedCollateralWorksIfOwner() public {
        ILendingStrategy.SetAllowedCollateralArg[] memory args = new ILendingStrategy.SetAllowedCollateralArg[](1);
        args[0] = ILendingStrategy.SetAllowedCollateralArg(address(nft), true);

        strategy.claimOwnership();
        strategy.setAllowedCollateral(args);

        assertTrue(strategy.isAllowed(address(nft)));
    }
}
