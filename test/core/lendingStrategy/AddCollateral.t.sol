// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseLendingStrategyTest} from "test/core/lendingStrategy/BaseLendingStrategy.ft.sol";
import {LendingStrategy} from "src/core/LendingStrategy.sol";
import {ILendingStrategy} from "src/interfaces/ILendingStrategy.sol";
import {TestERC721} from "test/mocks/TestERC721.sol";

contract AddCollateralTest is BaseLendingStrategyTest {
    function testAddCollateral() public {
        vm.startPrank(borrower);
        nft.approve(address(strategy), collateralId);
        strategy.addCollateral(
            vaultId,
            ILendingStrategy.Collateral(nft, collateralId),
            oracleInfo,
            sig
        );
    }

    function testAddCollateralFailsIfInvalidCollateral() public {
        TestERC721 invalidNFT = new TestERC721();
        vm.startPrank(borrower);
        nft.approve(address(strategy), collateralId);
        vm.expectRevert(LendingStrategy.InvalidCollateral.selector);
        strategy.addCollateral(
            vaultId,
            ILendingStrategy.Collateral(invalidNFT, collateralId),
            oracleInfo,
            sig
        );
    }

    function testAddCollateralMulticall() public {
        nft.mint(borrower, collateralId + 1);
        vm.startPrank(borrower);
        nft.setApprovalForAll(address(strategy), true);
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(
            strategy.addCollateral.selector,
            vaultId,
            ILendingStrategy.Collateral(nft, collateralId),
            oracleInfo,
            sig
        );
        data[1] = abi.encodeWithSelector(
            strategy.addCollateral.selector,
            vaultId,
            ILendingStrategy.Collateral(nft, collateralId + 1),
            oracleInfo,
            sig
        );
        strategy.multicall(data);
    }
}
