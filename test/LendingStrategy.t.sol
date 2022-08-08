// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";

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
    address borrower = address(1);
    address lender = address(2);

    function setUp() public {
        vm.deal(lender, 1e30);
        nft.mint(borrower, 1);
        vm.prank(borrower);
        nft.approve(address(strategy), 1);
    }

    function testExample() public {
        uint256 p = oracle.getTwap(
            strategy.pool(), address(strategy.debtSynth()), address(weth), 1, false
        );
        emit log_uint(p);
    }
}
