// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";

import {Base, ReservoirOracleUnderwriter} from "script/actions/Base.s.sol";
import {IPaprController} from "src/interfaces/IPaprController.sol";

contract StartAuction is Base {
    function run() public {
        oraclePriceKind = ReservoirOracleUnderwriter.PriceKind.TWAP;
        vm.startBroadcast();
        controller.startLiquidationAuction(
            deployer,
            IPaprController.Collateral({id: 40, addr: ERC721(0x8232c5Fd480C2a74d2f25d3362f262fF3511CE49)}),
            _getOracleInfoForCollateral(0x8232c5Fd480C2a74d2f25d3362f262fF3511CE49, 0.1e18)
        );
    }
}
