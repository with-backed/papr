// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {LendingStrategy} from "src/core/LendingStrategy.sol";

contract Base is Script {
    LendingStrategy strategy = LendingStrategy(vm.envAddress("STRATEGY"));
    uint256 pk = vm.envUint("PRIVATE_KEY");
    address deployer = vm.addr(pk);
}
