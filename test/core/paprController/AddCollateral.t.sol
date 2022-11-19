// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";

import {BasePaprControllerTest} from "test/core/paprController/BasePaprController.ft.sol";
import {PaprController} from "src/core/PaprController.sol";
import {IPaprController} from "src/interfaces/IPaprController.sol";
import {ReservoirOracleUnderwriter} from "src/core/ReservoirOracleUnderwriter.sol";
import {TestERC721} from "test/mocks/TestERC721.sol";

contract AddCollateralTest is BasePaprControllerTest {
    function testAddCollateral() public {
        vm.startPrank(borrower);
        nft.approve(address(strategy), collateralId);
        IPaprController.Collateral[] memory c = new IPaprController.Collateral[](1);
        c[0] = collateral;
        strategy.addCollateral(c);
        emit log_uint(strategy.maxDebt(oraclePrice));
        strategy.increaseDebt(borrower, collateral.addr, strategy.maxDebt(oraclePrice), oracleInfo);
        emit log_uint(strategy.liquidationPrice(borrower, collateral.addr, oraclePrice));
    }

    function testAddCollateralFailsIfInvalidCollateral() public {
        TestERC721 invalidNFT = new TestERC721();
        vm.startPrank(borrower);
        nft.approve(address(strategy), collateralId);
        vm.expectRevert(IPaprController.InvalidCollateral.selector);
        IPaprController.Collateral[] memory c = new IPaprController.Collateral[](1);
        c[0] = IPaprController.Collateral(ERC721(address(1)), 1);
        strategy.addCollateral(c);
    }

    function testAddCollateralMulticall() public {
        nft.mint(borrower, collateralId + 1);
        vm.startPrank(borrower);
        nft.setApprovalForAll(address(strategy), true);
        bytes[] memory data = new bytes[](1);
        IPaprController.Collateral[] memory c = new IPaprController.Collateral[](2);
        c[0] = IPaprController.Collateral(nft, collateralId);
        c[1] = IPaprController.Collateral(nft, collateralId + 1);
        data[0] = abi.encodeWithSelector(
            strategy.addCollateral.selector, c
        );
        strategy.multicall(data);
    }
}
