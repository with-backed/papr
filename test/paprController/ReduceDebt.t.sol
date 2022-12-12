// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {stdError} from "forge-std/Test.sol";
import {TickMath} from "fullrange/libraries/TickMath.sol";

import {BasePaprControllerTest} from "test/paprController/BasePaprController.ft.sol";
import {IPaprController} from "src/interfaces/IPaprController.sol";
import {PaprController} from "src/PaprController.sol";
import {UniswapHelpers} from "src/libraries/UniswapHelpers.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";
import {PaprToken} from "src/PaprToken.sol";

contract ReduceDebtTest is BasePaprControllerTest {
    event ReduceDebt(address indexed account, ERC721 indexed collateralAddress, uint256 amount);

    function testFuzzReduceDebt(uint256 debtToReduce) public {
        uint256 debt = _openMaxLoan();
        vm.assume(debtToReduce <= debt);

        vm.prank(borrower);
        controller.reduceDebt(borrower, collateral.addr, debtToReduce);

        IPaprController.VaultInfo memory vaultInfo = controller.vaultInfo(borrower, collateral.addr);

        assertEq(vaultInfo.debt, debt - debtToReduce);
        assertEq(debt - debtToReduce, debtToken.balanceOf(borrower));
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
