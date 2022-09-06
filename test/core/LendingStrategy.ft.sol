// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {TickMath} from "fullrange/libraries/TickMath.sol";
import {IQuoter} from "v3-periphery/interfaces/IQuoter.sol";
import {ISwapRouter} from "v3-periphery/interfaces/ISwapRouter.sol";

import {LendingStrategy} from "src/core/LendingStrategy.sol";
import {ILendingStrategy} from "src/interfaces/ILendingStrategy.sol";
import {StrategyFactory} from "src/core/StrategyFactory.sol";
import {FixedPointMathLib} from "src/libraries/FixedPointMathLib.sol";
import {TestERC721} from "test/mocks/TestERC721.sol";
import {TestERC20} from "test/mocks/TestERC20.sol";
import {INonfungiblePositionManager} from
    "test/mocks/uniswap/INonfungiblePositionManager.sol";

contract MainnetForking is Test {
    uint256 forkId =
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 15434809);
    INonfungiblePositionManager positionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    IQuoter quoter = IQuoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);
    ISwapRouter router = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
}

contract LendingStrategyForkingTest is Test, MainnetForking {
    TestERC721 nft = new TestERC721();
    TestERC20 underlying = new TestERC20();
    LendingStrategy strategy;

    uint256 collateralId = 1;
    address borrower = address(1);
    uint24 feeTier = 10000;
    bytes32 allowedCollateralRoot;

    ILendingStrategy.OnERC721ReceivedArgs safeTransferReceivedArgs;

    // global args for safe transfer receive data
    uint256 vaultId;
    uint256 vaultNonce;
    uint256 minOut;
    int256 debt = 1e18;
    uint160 sqrtPriceLimitX96;
    uint128 oraclePrice = 3e18;
    ILendingStrategy.OracleInfo oracleInfo;
    ILendingStrategy.Sig sig;

    //
    function setUp() public {
        StrategyFactory factory = new StrategyFactory();
        strategy = factory.newStrategy(
            "PUNKs Loans",
            "PL",
            "ipfs-link",
            allowedCollateralRoot,
            0.1e18,
            0.5e18,
            underlying
        );
        nft.mint(borrower, collateralId);
        vm.prank(borrower);
        nft.approve(address(strategy), collateralId);
        
        _provideLiquidityAtOneToOne();
        _populateOnReceivedArgs();
    }

    function testOpenVaultAddDebtAndSwap() public {
        vm.startPrank(borrower);
        safeTransferReceivedArgs.minOut = 1;
        safeTransferReceivedArgs.mintDebtOrProceedsTo = address(strategy.pool());
        nft.safeTransferFrom(
            borrower,
            address(strategy),
            collateralId,
            abi.encode(safeTransferReceivedArgs)
        );
    }

    function testAddDebtToExistingVault() public {
        vm.startPrank(borrower);
        (uint256 vaultId, uint256 vaultNonce) = strategy.openVault(borrower);
        safeTransferReceivedArgs.vaultId = vaultId;
        safeTransferReceivedArgs.vaultNonce = vaultNonce;
        nft.safeTransferFrom(
            borrower,
            address(strategy),
            collateralId,
            abi.encode(safeTransferReceivedArgs)
        );
    }

    function testAddDebtToExistingVaultRevertsIfNotVaultOwner() public {
        vm.startPrank(borrower);
        safeTransferReceivedArgs.vaultNonce = 1;
        vm.expectRevert(LendingStrategy.OnlyVaultOwner.selector);
        nft.safeTransferFrom(
            borrower,
            address(strategy),
            collateralId,
            abi.encode(safeTransferReceivedArgs)
        );
    }

    function _provideLiquidityAtOneToOne() internal {
        uint256 token0Amount;
        uint256 token1Amount;
        int24 tickLower;
        int24 tickUpper;

        if (strategy.token0IsUnderlying()) {
            token0Amount = 1e18;
            tickUpper = 200;
        } else {
            token1Amount = 1e18;
            tickLower = -200;
        }

        underlying.approve(address(positionManager), 1e18);
        underlying.mint(address(this), 1e18);

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
            address(this),
            block.timestamp + 1
        );

        positionManager.mint(mintParams);
    }

    function _populateOnReceivedArgs() internal {
        oracleInfo.price = oraclePrice;
        safeTransferReceivedArgs = ILendingStrategy.OnERC721ReceivedArgs({
            vaultId: vaultId,
            vaultNonce: vaultNonce,
            mintVaultTo: borrower,
            mintDebtOrProceedsTo: borrower,
            minOut: minOut,
            debt: debt,
            sqrtPriceLimitX96: _viableSqrtPriceLimit(),
            oracleInfo: oracleInfo,
            sig: sig
        });
    }

    function _viableSqrtPriceLimit() internal returns (uint160) {
        (uint160 sqrtPrice,,,,,,) = strategy.pool().slot0();
        int24 tick = TickMath.getTickAtSqrtRatio(sqrtPrice);

        // current strategy only swaps for underlying
        // if token0 is underlying, we want above the current sqrtPrice
        // if token1 is underlying, we want below the current sqrtPrice
        if (strategy.token0IsUnderlying()) {
            tick += 1;
        } else {
            tick -= 1;
        }

        return TickMath.getSqrtRatioAtTick(tick);
    }
}
