// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";

import {BaseLendingStrategyTest} from "test/core/lendingStrategy/BaseLendingStrategy.ft.sol";
import {LendingStrategy} from "src/core/LendingStrategy.sol";
import {ILendingStrategy} from "src/interfaces/ILendingStrategy.sol";
import {ReservoirOracleUnderwriter} from "src/core/ReservoirOracleUnderwriter.sol";
import {TestERC721} from "test/mocks/TestERC721.sol";

contract AddCollateralTest is BaseLendingStrategyTest {
    function testAddCollateral() public {
        vm.startPrank(borrower);
        nft.approve(address(strategy), collateralId);
        strategy.addCollateral(collateral);
    }

    function testAddCollateralFailsIfInvalidCollateral() public {
        TestERC721 invalidNFT = new TestERC721();
        vm.startPrank(borrower);
        nft.approve(address(strategy), collateralId);
        vm.expectRevert(ILendingStrategy.InvalidCollateral.selector);
        strategy.addCollateral(ILendingStrategy.Collateral(ERC721(address(1)), 1));
    }

    // function testAddCollateralFailsIfInvalidOracleSigner() public {
    //     vm.startPrank(borrower);
    //     nft.approve(address(strategy), collateralId);
    //     vm.expectRevert(ReservoirOracleUnderwriter.IncorrectOracleSigner.selector);
    //     oracleInfo.sig.v = 0;
    //     strategy.addCollateral(ILendingStrategy.Collateral(nft, collateralId), oracleInfo);
    // }

    // function testAddCollateralFailsIfOracleMessageForWrongCollateral() public {
    //     vm.startPrank(borrower);
    //     nft.approve(address(strategy), collateralId);
    //     ReservoirOracleUnderwriter.OracleInfo memory wrongInfo =
    //         _getOracleInfoForCollateral(ERC721(address(0)), underlying);
    //     vm.expectRevert(ReservoirOracleUnderwriter.WrongCollateralFromOracleMessage.selector);
    //     strategy.addCollateral(ILendingStrategy.Collateral(nft, collateralId), wrongInfo);
    // }

    // function testAddCollateralFailsIfOracleMessageHasWrongCurrency() public {
    //     vm.startPrank(borrower);
    //     nft.approve(address(strategy), collateralId);
    //     ReservoirOracleUnderwriter.OracleInfo memory wrongInfo = _getOracleInfoForCollateral(nft, ERC20(address(0)));
    //     vm.expectRevert(ReservoirOracleUnderwriter.WrongCurrencyFromOracleMessage.selector);
    //     strategy.addCollateral(ILendingStrategy.Collateral(nft, collateralId));
    // }

    function testAddCollateralMulticall() public {
        nft.mint(borrower, collateralId + 1);
        vm.startPrank(borrower);
        nft.setApprovalForAll(address(strategy), true);
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(
            strategy.addCollateral.selector, ILendingStrategy.Collateral(nft, collateralId), oracleInfo
        );
        data[1] = abi.encodeWithSelector(
            strategy.addCollateral.selector, ILendingStrategy.Collateral(nft, collateralId + 1), oracleInfo
        );
        strategy.multicall(data);
    }
}
