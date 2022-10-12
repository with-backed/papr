// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IUnderwriter {
    function underwritePriceForCollateral(
        uint256 tokenId,
        address contractAddress,
        address currencyForPriceAddress,
        bytes memory data
    ) external returns (uint256);
}
