pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {phUSDC} from "src/heroTestnet/phUSDC.sol";

contract phUSDCTest is Test {
    phUSDC phusdc;

    uint256 amount = 100;

    function setUp() public {
        phusdc = new phUSDC();
        phusdc.claimOwnership();
    }

    function testMintFailsIfNotOwner() public {
        vm.startPrank(address(1));
        vm.expectRevert("Ownable: caller is not the owner");
        phusdc.mint(address(1), amount);
        vm.stopPrank();
    }

    function testMintWorksIfOwner() public {
        phusdc.mint(address(1), amount);
        assertEq(amount, phusdc.balanceOf(address(1)));
    }

    function testNameSymbolDecimals() public {
        assertEq(phusdc.symbol(), "phUSDC");
        assertEq(phusdc.name(), "papr Heroes USDC");
        assertEq(phusdc.decimals(), 6);
    }

    function testBurnWorks() public {
        phusdc.mint(address(1), amount);
        vm.prank(address(1));
        phusdc.burn(amount);
        assertEq(phusdc.balanceOf(address(1)), 0);
    }

    function testStakingWorks() public {
        phusdc.mint(address(1), amount);
        vm.startPrank(address(1));

        phusdc.stake(amount);
        assertEq(phusdc.balanceOf(address(1)), 0);

        vm.warp(block.timestamp + 365 days);
        uint256 total = phusdc.unstake();
        assertEq(total, 109);
        assertEq(phusdc.balanceOf(address(1)), total);

        vm.stopPrank();
    }

    function testStakingFailsIfStakingMoreThanBalance() public {
        phusdc.mint(address(1), amount);
        vm.startPrank(address(1));

        phusdc.stake(amount);
        vm.expectRevert(phUSDC.StakingTooMuch.selector);
        phusdc.stake(amount);

        vm.stopPrank();
    }

    function testBeforeTokenTransferWorks() public {
        phusdc.mint(address(1), amount);
        vm.startPrank(address(1));

        phusdc.stake(amount);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        phusdc.transfer(address(2), 100);
        vm.stopPrank();
    }

    function testStakingWorksWhenStakingTwice() public {
        phusdc.mint(address(1), amount);
        vm.startPrank(address(1));

        phusdc.stake(amount / 2);
        assertEq(phusdc.balanceOf(address(1)), amount / 2);

        uint256 newTimestamp = block.timestamp + 365 days;
        vm.warp(newTimestamp);

        phusdc.stake(amount / 2);

        (uint256 amount, uint256 depositedAt) = phusdc.stakeInfo(address(1));
        assertEq(amount, 104);
        assertEq(depositedAt, newTimestamp);

        vm.warp(newTimestamp + 365 days);

        phusdc.unstake();
        assertEq(phusdc.balanceOf(address(1)), 110);

        vm.stopPrank();
    }
}
