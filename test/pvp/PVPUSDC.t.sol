pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {PVPUSDC} from "src/pvp/PVPUSDC.sol";

contract PVPUSDCTest is Test {
    PVPUSDC pvpUSDC;

    uint256 amount = 100;

    function setUp() public {
        pvpUSDC = new PVPUSDC();
        pvpUSDC.claimOwnership();
    }

    function testMintFailsIfNotOwner() public {
        vm.startPrank(address(1));
        vm.expectRevert("Ownable: caller is not the owner");
        pvpUSDC.mint(address(1), amount);
        vm.stopPrank();
    }

    function testMintWorksIfOwner() public {
        pvpUSDC.mint(address(1), amount);
        assertEq(amount, pvpUSDC.balanceOf(address(1)));
    }

    function testNameSymbolDecimals() public {
        assertEq(pvpUSDC.symbol(), "pUSDC");
        assertEq(pvpUSDC.name(), "Backed PVP USDC");
        assertEq(pvpUSDC.decimals(), 6);
    }

    function testBurnWorks() public {
        pvpUSDC.mint(address(1), amount);
        vm.prank(address(1));
        pvpUSDC.burn(amount);
        assertEq(pvpUSDC.balanceOf(address(1)), 0);
    }

    function testStakingWorks() public {
        pvpUSDC.mint(address(1), amount);
        vm.startPrank(address(1));

        pvpUSDC.stake(amount);
        assertEq(pvpUSDC.balanceOf(address(1)), 0);

        vm.warp(block.timestamp + 365 days);
        uint256 total = pvpUSDC.unstake();
        assertEq(total, 109);
        assertEq(pvpUSDC.balanceOf(address(1)), total);

        vm.stopPrank();
    }

    function testStakingFailsIfStakingMoreThanBalance() public {
        pvpUSDC.mint(address(1), amount);
        vm.startPrank(address(1));

        pvpUSDC.stake(amount);
        vm.expectRevert(PVPUSDC.StakingTooMuch.selector);
        pvpUSDC.stake(amount);

        vm.stopPrank();
    }

    function testBeforeTokenTransferWorks() public {
        pvpUSDC.mint(address(1), amount);
        vm.startPrank(address(1));

        pvpUSDC.stake(amount);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        pvpUSDC.transfer(address(2), 100);
        vm.stopPrank();
    }

    function testStakingWorksWhenStakingTwice() public {
        pvpUSDC.mint(address(1), amount);
        vm.startPrank(address(1));

        pvpUSDC.stake(amount / 2);
        assertEq(pvpUSDC.balanceOf(address(1)), amount / 2);

        uint256 newTimestamp = block.timestamp + 365 days;
        vm.warp(newTimestamp);

        pvpUSDC.stake(amount / 2);

        (uint256 amount, uint256 depositedAt) = pvpUSDC.stakedBalance(address(1));
        assertEq(amount, 104);
        assertEq(depositedAt, newTimestamp);

        vm.warp(newTimestamp + 365 days);

        pvpUSDC.unstake();
        assertEq(pvpUSDC.balanceOf(address(1)), 110);

        vm.stopPrank();
    }
}
