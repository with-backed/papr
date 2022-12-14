// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.17;

import {stdError} from "forge-std/Test.sol";
import {TickMath} from "fullrange/libraries/TickMath.sol";

import {BasePaprControllerTest} from "test/paprController/BasePaprController.ft.sol";
import {IPaprController} from "src/interfaces/IPaprController.sol";
import {PaprController} from "src/PaprController.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";
import {ReservoirOracleUnderwriter} from "src/ReservoirOracleUnderwriter.sol";

contract IncreaseDebtTest is BasePaprControllerTest {
    event IncreaseDebt(address indexed account, ERC721 indexed collateralAddress, uint256 amount);

    function testFuzzIncreaseDebt(uint256 debt) public {
        vm.assume(debt < type(uint200).max);
        vm.assume(debt < type(uint256).max / controller.maxLTV() / 2);

        oraclePrice = debt * 2;
        oracleInfo = _getOracleInfoForCollateral(nft, underlying);

        vm.startPrank(borrower);
        nft.approve(address(controller), collateralId);
        IPaprController.Collateral[] memory c = new IPaprController.Collateral[](1);
        c[0] = collateral;
        controller.addCollateral(c);

        controller.increaseDebt(borrower, collateral.addr, debt, oracleInfo);
        assertEq(debtToken.balanceOf(borrower), debt);
        assertEq(debt, controller.vaultInfo(borrower, collateral.addr).debt);
    }

    function testIncreaseDebtEmitsEvent() public {
        vm.startPrank(borrower);
        nft.approve(address(controller), collateralId);
        IPaprController.Collateral[] memory c = new IPaprController.Collateral[](1);
        c[0] = collateral;
        controller.addCollateral(c);

        vm.expectEmit(true, true, false, true);
        emit IncreaseDebt(borrower, collateral.addr, debt);
        controller.increaseDebt(borrower, collateral.addr, debt, oracleInfo);
    }

    function testFuzzIncreaseDebtRevertsIfTooMuchDebt(uint200 debt) public {
        vm.assume(debt > controller.maxDebt(oraclePrice));
        vm.startPrank(borrower);
        nft.approve(address(controller), collateralId);
        IPaprController.Collateral[] memory c = new IPaprController.Collateral[](1);
        c[0] = collateral;
        controller.addCollateral(c);

        uint256 maxDebt = controller.maxDebt(oraclePrice);

        vm.expectRevert(abi.encodeWithSelector(IPaprController.ExceedsMaxDebt.selector, debt, maxDebt));
        controller.increaseDebt(borrower, collateral.addr, debt, oracleInfo);
    }

    function testIncreaseDebtRevertsIfWrongPriceTypeFromOracle() public {
        vm.startPrank(borrower);
        nft.approve(address(controller), collateralId);
        IPaprController.Collateral[] memory c = new IPaprController.Collateral[](1);
        c[0] = collateral;
        controller.addCollateral(c);

        priceKind = ReservoirOracleUnderwriter.PriceKind.TWAP;
        oracleInfo = _getOracleInfoForCollateral(collateral.addr, underlying);

        vm.expectRevert(ReservoirOracleUnderwriter.WrongIdentifierFromOracleMessage.selector);
        controller.increaseDebt(borrower, collateral.addr, debt, oracleInfo);
        vm.stopPrank();
    }
}
