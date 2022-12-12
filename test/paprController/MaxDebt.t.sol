// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {TickMath} from "fullrange/libraries/TickMath.sol";

import {BasePaprControllerTest} from "test/paprController/BasePaprController.ft.sol";
import {IPaprController} from "src/interfaces/IPaprController.sol";
import {PaprController} from "src/PaprController.sol";
import {UniswapHelpers} from "src/libraries/UniswapHelpers.sol";

contract MaxDebt is BasePaprControllerTest {
    function testMaxDebtCalculatesCorrectly() public {
        uint256 max = controller.maxDebt(oraclePrice);
        uint256 newTarget = controller.newTarget();
        assertEq(max, (oraclePrice * controller.maxLTV()) / newTarget);
    }
}
