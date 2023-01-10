// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.17;

import {stdError} from "forge-std/Test.sol";
import {TickMath} from "fullrange/libraries/TickMath.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";

import {BasePaprControllerTest} from "./BasePaprController.ft.sol";
import {IPaprController} from "../../src/interfaces/IPaprController.sol";
import {PaprToken} from "../../src/PaprToken.sol";

contract ReduceDebtTest is BasePaprControllerTest {
    event ReduceDebt(address indexed account, ERC721 indexed collateralAddress, uint256 amount);

    function testFuzzReduceDebt(uint256 debtToReduce) public {
        uint256 debt = _openMaxLoan();

        vm.prank(borrower);
        controller.reduceDebt(borrower, collateral.addr, debtToReduce);

        IPaprController.VaultInfo memory vaultInfo = controller.vaultInfo(borrower, collateral.addr);

        uint256 reduced = debt < debtToReduce ? debt : debtToReduce;
        assertEq(vaultInfo.debt, debt - reduced);
        assertEq(debt - reduced, debtToken.balanceOf(borrower));
        vm.stopPrank();
    }

    function testReduceDebtEmitsReduceDebtEvent() public {
        uint256 debtAmount = _openMaxLoan();
        vm.startPrank(borrower);
        vm.expectEmit(true, true, false, true);
        emit ReduceDebt(borrower, collateral.addr, debtAmount);
        controller.reduceDebt(borrower, collateral.addr, debtAmount);
    }

    function testReduceDebtRevertsIfReducingMoreThanBalance() public {
        uint256 debt = _openMaxLoan();
        vm.startPrank(borrower);
        debtToken.transfer(address(0), 1);

        vm.expectRevert(stdError.arithmeticError);
        controller.reduceDebt(borrower, collateral.addr, debt);
        vm.stopPrank();
    }

    function testFuzzReduceDebtRevertsIfReducingMoreThanVaultDebt(uint200 debtToReduce) public {
        uint256 debt = _openMaxLoan();
        vm.assume(debtToReduce > debt);

        vm.prank(address(controller));
        PaprToken(address(debtToken)).mint(borrower, debtToReduce - debt);

        vm.expectRevert(stdError.arithmeticError);
        controller.reduceDebt(borrower, collateral.addr, debtToReduce);
        vm.stopPrank();
    }
}
