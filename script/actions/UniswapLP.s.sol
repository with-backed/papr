// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.17;

// import "forge-std/Script.sol";
// import {ERC20} from "solmate/tokens/ERC20.sol";
// import {INonfungiblePositionManager} from "test/mocks/uniswap/INonfungiblePositionManager.sol";
// import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

// import {PaprController} from "src/PaprController.sol";
// import {TestERC20} from "test/mocks/TestERC20.sol";
// import {Base} from "script/actions/Base.s.sol";

// contract UniswapLP is Base {
//     INonfungiblePositionManager positionManager =
//         INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
//     uint24 feeTier = 10000;

//     function run() public {
//         _provideLiquidityAtOneToOne();
//     }

//     function _provideLiquidityAtOneToOne() internal {
//         uint256 amount = 1e22;
//         uint256 token0Amount;
//         uint256 token1Amount;
//         int24 tickLower;
//         int24 tickUpper;

//         if (controller.token0IsUnderlying()) {
//             token0Amount = amount;
//             tickUpper = 200;
//         } else {
//             token1Amount = amount;
//             tickLower = -200;
//         }

//         ERC20 underlying = controller.underlying();

//         vm.startBroadcast();

//         underlying.approve(address(positionManager), amount);
//         TestERC20(address(underlying)).mint(deployer, amount);

//         IUniswapV3Pool pool = IUniswapV3Pool(controller.pool());

//         INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager.MintParams(
//             pool.token0(),
//             pool.token1(),
//             feeTier,
//             tickLower,
//             tickUpper,
//             token0Amount,
//             token1Amount,
//             0,
//             0,
//             address(this),
//             block.timestamp + 100
//         );

//         positionManager.mint(mintParams);
//     }
// }
