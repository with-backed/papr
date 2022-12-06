// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";

import {BasePaprControllerTest} from "test/paprController/BasePaprController.ft.sol";
import {PaprController} from "src/PaprController.sol";
import {IPaprController} from "src/interfaces/IPaprController.sol";
import {ReservoirOracleUnderwriter} from "src/ReservoirOracleUnderwriter.sol";
import {TestERC721} from "test/mocks/TestERC721.sol";

contract AddCollateralTest is BasePaprControllerTest {
    function testAddCollateral() public {
        vm.startPrank(borrower);
        nft.approve(address(strategy), collateralId);
        strategy.addCollateral(collateral);
        strategy.increaseDebt(borrower, collateral.addr, strategy.maxDebt(oraclePrice), oracleInfo);
    }

    function testAddCollateralFailsIfInvalidCollateral() public {
        TestERC721 invalidNFT = new TestERC721();
        vm.startPrank(borrower);
        nft.approve(address(strategy), collateralId);
        vm.expectRevert(IPaprController.InvalidCollateral.selector);
        strategy.addCollateral(IPaprController.Collateral(ERC721(address(1)), 1));
    }

    function testAddCollateralMulticall() public {
        nft.mint(borrower, collateralId + 1);
        vm.startPrank(borrower);
        nft.setApprovalForAll(address(strategy), true);
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(
            strategy.addCollateral.selector, IPaprController.Collateral(nft, collateralId), oracleInfo
        );
        data[1] = abi.encodeWithSelector(
            strategy.addCollateral.selector, IPaprController.Collateral(nft, collateralId + 1), oracleInfo
        );
        strategy.multicall(data);
    }
}
