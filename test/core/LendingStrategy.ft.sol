// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";
import {TickMath} from "fullrange/libraries/TickMath.sol";
import {IQuoter} from "v3-periphery/interfaces/IQuoter.sol";
import {ISwapRouter} from "v3-periphery/interfaces/ISwapRouter.sol";

import {Oracle} from "src/squeeth/Oracle.sol";
import {LendingStrategy} from "src/core/LendingStrategy.sol";
import {ILendingStrategy} from "src/interfaces/ILendingStrategy.sol";
import {StrategyFactory} from "src/core/StrategyFactory.sol";
import {FixedPointMathLib} from "src/libraries/FixedPointMathLib.sol";

contract TestERC721 is ERC721("TEST", "TEST") {
    function mint(address to, uint256 id) external {
        _mint(to, id);
    }

    function tokenURI(uint256 id)
        public
        view
        override
        returns (string memory)
    {}
}

interface INonfungiblePositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    /// @notice Creates a new position wrapped in a NFT
    /// @dev Call this when the pool does exist and is initialized. Note that if the pool is created but not initialized
    /// a method does not exist, i.e. the pool is assumed to be initialized.
    /// @param params The params necessary to mint a position, encoded as `MintParams` in calldata
    /// @return tokenId The ID of the token that represents the minted position
    /// @return liquidity The amount of liquidity for this position
    /// @return amount0 The amount of token0
    /// @return amount1 The amount of token1
    function mint(MintParams calldata params)
        external
        payable
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );
}

contract LendingStrategyForkingTest is Test {
    uint256 forkId =
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 15434809);
    StrategyFactory factory;

    TestERC721 nft = new TestERC721();
    WETH weth = WETH(payable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));
    Oracle oracle = new Oracle();
    LendingStrategy strategy;
    INonfungiblePositionManager positionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    IQuoter quoter = IQuoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);
    ISwapRouter router = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    address borrower = address(1);
    address lender = address(2);
    uint24 feeTier = 10000;
    bytes32 allowedCollateralRoot;
    int24 tickLower;
    int24 tickUpper;

    event VaultCreated(
        bytes32 indexed vaultKey,
        address indexed mintTo,
        uint256 tokenId,
        uint256 amount
    );
    event DebtAdded(bytes32 indexed vaultKey, uint256 amount);
    event DebtReduced(bytes32 indexed vaultKey, uint256 amount);
    event VaultClosed(bytes32 indexed vaultKey, uint256 tokenId);
    event NormalizationFactorUpdated(uint128 oldNorm, uint128 newNorm);

    function setUp() public {
        factory = new StrategyFactory();
        strategy = factory.newStrategy(
            "PUNKs Loans", "PL", allowedCollateralRoot, 1e17, 5e17, weth
        );
        nft.mint(borrower, 1);
        vm.prank(borrower);
        nft.approve(address(strategy), 1);

        address tokenA = address(strategy.debtToken());
        address tokenB = address(weth);
        (address token0, address token1) =
            tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        uint256 token0Amount;
        uint256 token1Amount;

        if (token0 == tokenB) {
            token0Amount = 1e18;
        } else {
            token1Amount = 1e18;
        }

        vm.startPrank(lender);
        weth.approve(address(positionManager), 1e18);
        vm.deal(lender, 1e30);
        weth.deposit{value: 1e30}();

        vm.warp(block.timestamp + 1);

        if (strategy.token0IsUnderlying()) {
            tickUpper = 200;
        } else {
            tickLower = -200;
        }

        INonfungiblePositionManager.MintParams memory mintParams =
        INonfungiblePositionManager.MintParams(
            strategy.pool().token0(),
            strategy.pool().token1(),
            feeTier,
            tickLower,
            tickUpper,
            token0Amount,
            token1Amount,
            0,
            0,
            lender,
            block.timestamp + 1
        );

        positionManager.mint(mintParams);
        vm.stopPrank();
    }

    bytes[] data;

    function testBorrow() public {
        vm.warp(block.timestamp + 1);
        vm.startPrank(borrower);
        ILendingStrategy.OnERC721ReceivedArgs memory args = ILendingStrategy
            .OnERC721ReceivedArgs(
            0,
            borrower,
            borrower,
            1,
            1e17,
            TickMath.getSqrtRatioAtTick(
                strategy.token0IsUnderlying() ? tickUpper - 1 : tickLower + 1
            ),
            ILendingStrategy.OracleInfo(3e18, ILendingStrategy.OracleInfoPeriod.SevenDays),
            ILendingStrategy.Sig({v: 1, r: keccak256("x"), s: keccak256("x")})
        );
        emit log_uint(block.timestamp);
        emit log_uint(strategy.lastUpdated());

        emit log_uint(strategy.mark());
        nft.safeTransferFrom(borrower, address(strategy), 1, abi.encode(args));
        vm.warp(block.timestamp + 100000);
        emit log_uint(strategy.mark());

        // uint256 q = quoter.quoteExactInputSingle(
        //     address(strategy.debtToken()),
        //     address(strategy.underlying()),
        //     feeTier,
        //     1e18,
        //     0
        // );
        // emit log_named_uint("quote 1 eth", q);

        // ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
        //     .ExactInputSingleParams({
        //     tokenIn: address(strategy.debtToken()),
        //     tokenOut: address(strategy.underlying()),
        //     fee: feeTier,
        //     recipient: borrower,
        //     deadline: block.timestamp + 15,
        //     amountIn: 1e18,
        //     amountOutMinimum: 0,
        //     sqrtPriceLimitX96: 0
        // });

        // strategy.debtToken().approve(address(router), 1e18);

        // router.exactInputSingle(params);
    }
}
