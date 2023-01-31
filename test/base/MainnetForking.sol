// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

contract MainnetForking is Test {
    uint256 forkId = vm.createSelectFork(vm.envString("GOERLI_RPC_URL"), 8405083);
}
