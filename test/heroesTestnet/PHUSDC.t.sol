pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {PHUSDC} from "src/heroesTestnet/phUSDC.sol";

contract PHUSDCTest is Test {
    PHUSDC phUSDC;

    uint256 amount = 100;

    function setUp() public {
        phUSDC = new PHUSDC();
        phUSDC.claimOwnership();
    }

    function testMintFailsIfNotOwner() public {
        vm.startPrank(address(1));
        vm.expectRevert("Ownable: caller is not the owner");
        phUSDC.mint(address(1), amount);
        vm.stopPrank();
    }

    function testMintWorksIfOwner() public {
        phUSDC.mint(address(1), amount);
        assertEq(amount, phUSDC.balanceOf(address(1)));
    }

    function testNameSymbolDecimals() public {
        assertEq(phUSDC.symbol(), "phUSDC");
        assertEq(phUSDC.name(), "PAPR Heroes USDC");
        assertEq(phUSDC.decimals(), 6);
    }

    function testBurnWorks() public {
        phUSDC.mint(address(1), amount);
        vm.prank(address(1));
        phUSDC.burn(amount);
        assertEq(phUSDC.balanceOf(address(1)), 0);
    }

    function testStakingWorks() public {
        phUSDC.mint(address(1), amount);
        vm.startPrank(address(1));

        phUSDC.stake(amount);
        assertEq(phUSDC.balanceOf(address(1)), 0);

        vm.warp(block.timestamp + 365 days);
        uint256 total = phUSDC.unstake();
        assertEq(total, 109);
        assertEq(phUSDC.balanceOf(address(1)), total);

        vm.stopPrank();
    }

    function testStakingFailsIfStakingMoreThanBalance() public {
        phUSDC.mint(address(1), amount);
        vm.startPrank(address(1));

        phUSDC.stake(amount);
        vm.expectRevert(PHUSDC.StakingTooMuch.selector);
        phUSDC.stake(amount);

        vm.stopPrank();
    }

    function testBeforeTokenTransferWorks() public {
        phUSDC.mint(address(1), amount);
        vm.startPrank(address(1));

        phUSDC.stake(amount);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        phUSDC.transfer(address(2), 100);
        vm.stopPrank();
    }

    function testStakingWorksWhenStakingTwice() public {
        phUSDC.mint(address(1), amount);
        vm.startPrank(address(1));

        phUSDC.stake(amount / 2);
        assertEq(phUSDC.balanceOf(address(1)), amount / 2);

        uint256 newTimestamp = block.timestamp + 365 days;
        vm.warp(newTimestamp);

        phUSDC.stake(amount / 2);

        (uint256 amount, uint256 depositedAt) = phUSDC.stakeInfo(address(1));
        assertEq(amount, 104);
        assertEq(depositedAt, newTimestamp);

        vm.warp(newTimestamp + 365 days);

        phUSDC.unstake();
        assertEq(phUSDC.balanceOf(address(1)), 110);

        vm.stopPrank();
    }
}
