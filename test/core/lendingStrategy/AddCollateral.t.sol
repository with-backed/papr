// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseLendingStrategyTest} from "test/core/lendingStrategy/BaseLendingStrategy.ft.sol";
import {LendingStrategy} from "src/core/LendingStrategy.sol";
import {ILendingStrategy} from "src/interfaces/ILendingStrategy.sol";
import {IUnderwriter} from "src/interfaces/IUnderwriter.sol";
import {TestERC721} from "test/mocks/TestERC721.sol";

contract AddCollateralTest is BaseLendingStrategyTest {
    function testAddCollateral() public {
        vm.startPrank(borrower);
        nft.approve(address(strategy), collateralId);
        strategy.addCollateral(vaultNonce, ILendingStrategy.Collateral(nft, collateralId), oracleInfo);
    }

    function testAddCollateralFailsIfInvalidCollateral() public {
        TestERC721 invalidNFT = new TestERC721();
        vm.startPrank(borrower);
        nft.approve(address(strategy), collateralId);
        vm.expectRevert(ILendingStrategy.InvalidCollateral.selector);
        strategy.addCollateral(vaultNonce, ILendingStrategy.Collateral(invalidNFT, collateralId), oracleInfo);
    }

    function testAddCollateralFailsIfInvalidOracleSigner() public {
        vm.startPrank(borrower);
        nft.approve(address(strategy), collateralId);
        vm.expectRevert(IUnderwriter.IncorrectOracleSigner.selector);
        oracleInfo.sig.v = 0;
        strategy.addCollateral(vaultNonce, ILendingStrategy.Collateral(nft, collateralId), oracleInfo);
    }

    function testAddCollateralFailsIfOracleMessageForWrongCollateral() public {
        vm.startPrank(borrower);
        nft.approve(address(strategy), collateralId);
        IUnderwriter.OracleInfo memory wrongInfo = getOracleInfoForCollateral(address(0), address(underlying));
        vm.expectRevert(IUnderwriter.InvalidOracleMessage.selector);
        strategy.addCollateral(vaultNonce, ILendingStrategy.Collateral(nft, collateralId), wrongInfo);
    }

    function testAddCollateralMulticall() public {
        nft.mint(borrower, collateralId + 1);
        vm.startPrank(borrower);
        nft.setApprovalForAll(address(strategy), true);
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(
            strategy.addCollateral.selector, vaultId, ILendingStrategy.Collateral(nft, collateralId), oracleInfo
        );
        data[1] = abi.encodeWithSelector(
            strategy.addCollateral.selector, vaultId, ILendingStrategy.Collateral(nft, collateralId + 1), oracleInfo
        );
        strategy.multicall(data);
    }
}
