import "forge-std/Test.sol";

import {LendingStrategy} from "src/core/LendingStrategy.sol";
import {ILendingStrategy} from "src/interfaces/ILendingStrategy.sol";
import {StrategyFactory} from "src/core/StrategyFactory.sol";
import {TestERC721} from "test/mocks/TestERC721.sol";
import {TestERC20} from "test/mocks/TestERC20.sol";

contract SetAllowedCollateralTest is Test {
    function setUp() public {
        StrategyFactory factory = new StrategyFactory();
        strategy = factory.newStrategy(
            "PUNKs Loans",
            "PL",
            "ipfs-link",
            0.1e18,
            0.5e18,
            underlying
        );
        ILendingStrategy.SetAllowedCollateralArg[]
            memory args = new ILendingStrategy.SetAllowedCollateralArg[](1);
        args[0] = ILendingStrategy.SetAllowedCollateralArg(address(nft), true);
        strategy.setAllowedCollateral(args);
        nft.mint(borrower, collateralId);
        vm.prank(borrower);
        nft.approve(address(strategy), collateralId);

        _provideLiquidityAtOneToOne();
        _populateOnReceivedArgs();
    }
}
