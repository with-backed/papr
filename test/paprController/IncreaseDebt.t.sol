// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {TickMath} from "fullrange/libraries/TickMath.sol";

import {BasePaprControllerTest} from "test/paprController/BasePaprController.ft.sol";
import {IPaprController} from "src/interfaces/IPaprController.sol";
import {PaprController} from "src/PaprController.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";

contract IncreaseDebtTest is BasePaprControllerTest {
    event IncreaseDebt(
        address indexed account,
        ERC721 indexed collateralAddress,
        uint256 amount
    );

    function testFuzzIncreaseDebt(uint256 debt) public {
        vm.assume(debt < controller.maxDebt(oraclePrice));
        vm.startPrank(borrower);
        nft.approve(address(controller), collateralId);
        controller.addCollateral(collateral);

        vm.expectEmit(true, true, true, true);
        emit IncreaseDebt(borrower, collateral.addr, debt);
        controller.increaseDebt(borrower, collateral.addr, debt, oracleInfo);
        assertEq(debtToken.balanceOf(borrower), debt);
        assertEq(debt, controller.vaultInfo(borrower, collateral.addr).debt);
    }

    function testFuzzIncreaseDebtRevertsIfTooMuchDebt(uint200 debt) public {
        vm.assume(debt > controller.maxDebt(oraclePrice));
        vm.startPrank(borrower);
        nft.approve(address(controller), collateralId);
        controller.addCollateral(collateral);

        uint256 maxDebt = controller.maxDebt(oraclePrice);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPaprController.ExceedsMaxDebt.selector,
                debt,
                maxDebt
            )
        );
        controller.increaseDebt(borrower, collateral.addr, debt, oracleInfo);
    }

    function testFuzzIncreaseDebtRevertsIfDebtGreaterThanMaxUint200(
        uint256 debt
    ) public {
        vm.assume(debt > (2**200) - 1);
        vm.startPrank(borrower);
        nft.approve(address(controller), collateralId);
        controller.addCollateral(collateral);

        uint256 maxDebt = controller.maxDebt(oraclePrice);

        vm.expectRevert();
        controller.increaseDebt(borrower, collateral.addr, debt, oracleInfo);
    }
}
