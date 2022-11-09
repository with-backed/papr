// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BasePaprControllerTest} from "test/core/paprController/BasePaprController.ft.sol";
// import {PaprController} from "src/core/PaprController.sol";
import {IPaprController} from "src/interfaces/IPaprController.sol";
// import {ReservoirOracleUnderwriter} from "src/core/ReservoirOracleUnderwriter.sol";
// import {TestERC721} from "test/mocks/TestERC721.sol";

contract LiquidationPrice is BasePaprControllerTest {
    function testRevertsIfNoDebt() public {
        vm.expectRevert(IPaprController.AccountHasNoDebt.selector);
        strategy.liquidationPrice(borrower, collateral.addr, oraclePrice);
    }
}
