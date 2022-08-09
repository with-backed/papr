// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";
import {TickMath} from "fullrange/libraries/TickMath.sol";
import {INonfungiblePositionManager} from "v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

import {Oracle} from "src/squeeth/Oracle.sol";
import {LendingStrategy} from "src/LendingStrategy.sol";

contract TestERC721 is ERC721("TEST", "TEST") {
    function mint(address to, uint256 id) external {
        _mint(to, id);
    }

    function tokenURI(uint256 id) public view override returns (string memory) {

    }
}

contract LendingStrategyTest is Test {
    TestERC721 nft = new TestERC721();
    ERC20 weth = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    Oracle oracle = new Oracle();
    LendingStrategy strategy =
        new LendingStrategy("PUNKs Loans", "PL", weth, oracle);
    INonfungiblePositionManager positionManager = INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    address borrower = address(1);
    address lender = address(2);

    function setUp() public {
        vm.deal(lender, 1e30);
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

        vm.prank(lender);
        weth.approve(address(positionManager), 1e18);

        INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager.MintParams(
            strategy.pool().token0(),
            strategy.pool().token1(),
            10000,
            TickMath.MIN_TICK(),
            TickMath.MAX_TICK(),
            token0Amount,
            token1Amount,
            token0Amount, 
            token1Amount,
            lender,
            block.timestamp
        );

        positionManager.mint(mintParams);
    }

    function testExample() public {
        uint256 p = oracle.getTwap(
            strategy.pool(), address(strategy.debtSynth()), address(weth), 1, false
        );
        emit log_uint(p);
    }
}
