// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";
import {TickMath} from "fullrange/libraries/TickMath.sol";

import {Oracle} from "src/squeeth/Oracle.sol";
import {LendingStrategy} from "src/LendingStrategy.sol";

contract TestERC721 is ERC721("TEST", "TEST") {
    function mint(address to, uint256 id) external {
        _mint(to, id);
    }

    function tokenURI(uint256 id) public view override returns (string memory) {

    }
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


contract LendingStrategyTest is Test {
    TestERC721 nft = new TestERC721();
    WETH weth = WETH(payable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));
    Oracle oracle = new Oracle();
    LendingStrategy strategy;
    INonfungiblePositionManager positionManager = INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    address borrower = address(1);
    address lender = address(2);

    function setUp() public {
        vm.warp(1);
        strategy = new LendingStrategy("PUNKs Loans", "PL", weth, oracle);
        nft.mint(borrower, 1);
        vm.prank(borrower);
        nft.approve(address(strategy), 1);

        address tokenA = address(strategy.debtSynth());
        address tokenB = address(weth);
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
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
        // weth.approve(address(strategy.pool()), 1e18);

        vm.warp(10);

        uint160 oneToOnePrice = uint160(((10 ** ERC20(token1).decimals()) << 96) / (10 ** ERC20(token0).decimals()) / 2);

        INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager.MintParams(
            strategy.pool().token0(),
            strategy.pool().token1(),
            10000,
            0,
            200,
            token0Amount,
            token1Amount,
            0, 
            0,
            lender,
            block.timestamp + 1
        );

        strategy.pool().initialize(TickMath.getSqrtRatioAtTick(0));
        positionManager.mint(mintParams);
    }

    function testExample() public {
        vm.warp(1 weeks);
        uint256 p = oracle.getTwap(
            address(strategy.pool()), address(strategy.debtSynth()), address(weth), uint32(1), false
        );
        emit log_named_uint('contract thinks each debt token should be worth', strategy.index());
        emit log_named_uint('but debt token is actually worth', strategy.mark(1));
        emit log_named_uint('so contract multiplies normal interest by', strategy.targetMultiplier());
        emit log_named_uint('and so, for the contract, each debt token is now worth', strategy.newNorm());
    }
}
