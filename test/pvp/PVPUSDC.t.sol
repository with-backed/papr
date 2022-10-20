pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {PVPUSDC} from "src/pvp/PVPUSDC.sol";
import {PVPStaker} from "src/pvp/PVPStaker.sol";

contract PVPUSDCTest is Test {
    PVPUSDC pvpUSDC;
    PVPStaker staker;

    function setUp() public {
        pvpUSDC = new PVPUSDC();
        staker = new PVPStaker(pvpUSDC);
        pvpUSDC.claimOwnership();
        pvpUSDC.setStaker(address(staker));
    }

    function testMintFailsIfNotOwner() public {
        vm.startPrank(address(1));
        vm.expectRevert("Ownable: caller is not the owner");
        pvpUSDC.mint(address(1), 100);
        vm.stopPrank();
    }

    function testMintWorksIfOwner() public {
        pvpUSDC.mint(address(1), 100);
        assertEq(100, pvpUSDC.balanceOf(address(1)));
    }

    function testStakingWorks() public {
        pvpUSDC.mint(address(1), 1e6);
        vm.startPrank(address(1));
        pvpUSDC.approve(address(staker), 1e6);
        staker.stake(1e6);

        vm.warp(block.timestamp + 365 days);
        uint256 total = staker.unstake();
        assertEq(total, 10999905);
        assertEq(pvpUSDC.balanceOf(address(1)), total);
        assertEq(pvpUSDC.balanceOf(address(staker)), 0);

        vm.stopPrank();
    }

    function testStakeFailsIfNotLongerThanOneDay() public {
        pvpUSDC.mint(address(1), 1e6);
        vm.startPrank(address(1));
        pvpUSDC.approve(address(staker), 1e6);
        staker.stake(1e6);

        vm.warp(block.timestamp + 10);
        vm.expectRevert(PVPStaker.StakeTooShort.selector);
        staker.unstake();

        vm.stopPrank();
    }

    function testStakeFailsIfAlreadyStaking() public {
        pvpUSDC.mint(address(1), 1e6);
        vm.startPrank(address(1));
        pvpUSDC.approve(address(staker), 1e6);
        staker.stake(1e4);

        vm.expectRevert(PVPStaker.AlreadyStaking.selector);
        staker.stake(1e2);

        vm.stopPrank();
    }
}
