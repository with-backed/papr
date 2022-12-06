// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BasePaprControllerTest} from "test/paprController/BasePaprController.ft.sol";
import {IPaprController} from "src/interfaces/IPaprController.sol";

contract LiquidationPrice is BasePaprControllerTest {
    function testRevertsIfNoDebt() public {
        vm.expectRevert(IPaprController.AccountHasNoDebt.selector);
        strategy.liquidationPrice(borrower, collateral.addr, oraclePrice);
    }
}
