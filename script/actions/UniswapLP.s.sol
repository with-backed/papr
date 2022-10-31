// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {INonfungiblePositionManager} from "test/mocks/uniswap/INonfungiblePositionManager.sol";

import {LendingStrategy} from "src/core/LendingStrategy.sol";
import {TestERC20} from "test/mocks/TestERC20.sol";

contract UniswapLP is Script {
    LendingStrategy strategy = LendingStrategy(vm.envAddress("STRATEGY"));
    INonfungiblePositionManager positionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    uint256 pk = vm.envUint("PRIVATE_KEY");
    address deployer = vm.addr(pk);
    uint24 feeTier = 10000;

    function run() public {
        _provideLiquidityAtOneToOne();
    }

    function _provideLiquidityAtOneToOne() internal {
        uint256 amount = 1e19;
        uint256 token0Amount;
        uint256 token1Amount;
        int24 tickLower;
        int24 tickUpper;

        if (strategy.token0IsUnderlying()) {
            token0Amount = amount;
            tickUpper = 200;
        } else {
            token1Amount = amount;
            tickLower = -200;
        }

        ERC20 underlying = strategy.underlying();

        vm.startBroadcast();

        underlying.approve(address(positionManager), amount);
        TestERC20(address(underlying)).mint(deployer, amount);

        INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager.MintParams(
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
            block.timestamp + 100
        );

        positionManager.mint(mintParams);
    }
}
