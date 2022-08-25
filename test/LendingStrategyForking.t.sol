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
import {
    LendingStrategy
} from "src/LendingStrategy.sol";
import {
    ILendingStrategy
} from "src/interfaces/ILendingStrategy.sol";
import {StrategyFactory} from "src/StrategyFactory.sol";
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
        vm.warp(1);
        factory = new StrategyFactory();
        strategy = factory.newStrategy("PUNKs Loans", "PL", nft, weth);
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

        vm.warp(10);

        INonfungiblePositionManager.MintParams memory mintParams =
        INonfungiblePositionManager.MintParams(
            strategy.pool().token0(),
            strategy.pool().token1(),
            feeTier,
            -200,
            0,
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

    function testBorrow() public {
        vm.warp(block.timestamp + 1);
        vm.startPrank(borrower);
        // nft.transferFrom(borrower, address(strategy), 1);

        ILendingStrategy.OpenVaultRequest memory request = ILendingStrategy.OpenVaultRequest(
            borrower,
            1e18,
            ILendingStrategy.Collateral({addr: nft, id: 1}),
            ILendingStrategy.OracleInfo({price: 3e18, period: ILendingStrategy.OracleInfoPeriod.SevenDays}),
            ILendingStrategy.Sig({v: 1, r: keccak256("x"), s: keccak256("x")})
        );
        strategy.updateNormalization();

        nft.safeTransferFrom(
            borrower, address(strategy), 1, abi.encode(request)
        );

        uint256 q = quoter.quoteExactInputSingle(
            address(strategy.debtToken()),
            address(strategy.underlying()),
            feeTier,
            1e18,
            0
        );
        emit log_named_uint("quote 1 eth", q);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
            tokenIn: address(strategy.debtToken()),
            tokenOut: address(strategy.underlying()),
            fee: feeTier,
            recipient: borrower,
            deadline: block.timestamp + 15,
            amountIn: 1e18,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        strategy.debtToken().approve(address(router), 1e18);

        router.exactInputSingle(params);
    }
}
