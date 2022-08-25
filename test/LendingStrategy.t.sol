// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {
    ILendingStrategy
} from "src/interfaces/ILendingStrategy.sol";

contract LendingStrategyTest is Test {
    

    function testDecode() public {
        bytes[] memory x;
        // x.push(abi.encode("x"));
        bytes[] memory y = abi.decode(abi.encode(x), (bytes[]));
    }
}
