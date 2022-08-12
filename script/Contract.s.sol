// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {DebtToken} from "src/DebtToken.sol";
import {Oracle} from "src/squeeth/Oracle.sol";

contract ContractScript is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        new Oracle();
    }
}
