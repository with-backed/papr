// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

contract MainnetForking is Test {
    uint256 forkId = vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 15434809);
}
