// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";

import {Base} from "script/actions/Base.s.sol";
import {ILendingStrategy} from "src/interfaces/ILendingStrategy.sol";

contract StartAuction is Base {
    // function run() public {
    //     vm.startBroadcast();
    //     strategy.startLiquidationAuction(
    //         deployer, ILendingStrategy.Collateral({id: 20, addr: ERC721(0x8232c5Fd480C2a74d2f25d3362f262fF3511CE49)}), oracleInfo
    //     );
    // }
}
