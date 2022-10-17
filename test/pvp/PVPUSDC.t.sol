pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {PVPUSDC} from "src/pvp/PVPUSDC.sol";

contract PVPUSDCTest is Test {
    PVPUSDC pvpUSDC;

    function setUp() public {
        pvpUSDC = new PVPUSDC();
        pvpUSDC.claimOwnership();
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
}
