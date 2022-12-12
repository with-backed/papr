// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {TickMath} from "fullrange/libraries/TickMath.sol";

import {BasePaprControllerTest} from "test/paprController/BasePaprController.ft.sol";
import {IPaprController} from "src/interfaces/IPaprController.sol";
import {PaprController} from "src/PaprController.sol";
import {UniswapHelpers} from "src/libraries/UniswapHelpers.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";
import {PaprToken} from "src/PaprToken.sol";

contract ReduceDebtTest is BasePaprControllerTest {
    event ReduceDebt(
        address indexed account,
        ERC721 indexed collateralAddress,
        uint256 amount
    );

    function testFuzzReduceDebt(uint256 debtToReduce) public {
        vm.assume(debtToReduce <= debt);
        vm.startPrank(borrower);
        nft.approve(address(controller), collateralId);

        controller.addCollateral(collateral);
        controller.increaseDebt(borrower, collateral.addr, debt, oracleInfo);
        IPaprController.VaultInfo memory vaultInfo = controller.vaultInfo(
            borrower,
            collateral.addr
        );
        assertEq(vaultInfo.debt, debt);
        assertEq(debt, debtToken.balanceOf(borrower));

        vm.expectEmit(true, true, true, true);
        emit ReduceDebt(borrower, collateral.addr, debt);
        controller.reduceDebt(borrower, collateral.addr, debt);
        vaultInfo = controller.vaultInfo(borrower, collateral.addr);

        assertEq(vaultInfo.debt, 0);
        assertEq(0, debtToken.balanceOf(borrower));
        vm.stopPrank();
    }

    function testFuzzReduceDebtRevertsIfReducingMoreThanBalance(
        uint200 debtToReduce,
        uint256 borrowerPaprBalance
    ) public {
        vm.assume(
            debtToReduce > borrowerPaprBalance && borrowerPaprBalance < debt
        );
        vm.startPrank(borrower);
        nft.approve(address(controller), collateralId);

        controller.addCollateral(collateral);
        controller.increaseDebt(borrower, collateral.addr, debt, oracleInfo);
        IPaprController.VaultInfo memory vaultInfo = controller.vaultInfo(
            borrower,
            collateral.addr
        );
        assertEq(vaultInfo.debt, debt);
        assertEq(debt, debtToken.balanceOf(borrower));

        // set borrowers papr balance equal to borrowerPaprBalance
        debtToken.transfer(address(0), debt - borrowerPaprBalance);

        vm.expectRevert();
        controller.reduceDebt(borrower, collateral.addr, debtToReduce);
        vm.stopPrank();
    }

    function testFuzzReduceDebtRevertsIfReducingMoreThanVaultDebt(
        uint200 debtToReduce
    ) public {
        vm.assume(debtToReduce > debt);
        vm.startPrank(borrower);
        nft.approve(address(controller), collateralId);

        controller.addCollateral(collateral);
        controller.increaseDebt(borrower, collateral.addr, debt, oracleInfo);
        IPaprController.VaultInfo memory vaultInfo = controller.vaultInfo(
            borrower,
            collateral.addr
        );
        assertEq(vaultInfo.debt, debt);
        assertEq(debt, debtToken.balanceOf(borrower));
        vm.stopPrank();

        vm.prank(address(controller));
        PaprToken(address(debtToken)).mint(borrower, debtToReduce - debt);

        vm.expectRevert();
        controller.reduceDebt(borrower, collateral.addr, debtToReduce);
        vm.stopPrank();
    }
}
