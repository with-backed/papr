// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Test.sol";

import {ReservoirOracle} from "@reservoir/ReservoirOracle.sol";

import {ReservoirOracleUnderwriter, ERC721} from "../src/ReservoirOracleUnderwriter.sol";
import {OracleSigUtils} from "./OracleSigUtils.sol";
import {OracleTest, ERC20} from "./base/OracleTest.sol";

contract ReservoirOracleUnderwriterTest is Test, OracleTest {
    uint256 signerPrivateKey = 0xA11CE;
    address signer = vm.addr(signerPrivateKey);
    ERC20 quoteCurrency = ERC20(address(4));
    ERC721 nft = ERC721(address(3));
    ReservoirOracleUnderwriter oracle = new ReservoirOracleUnderwriter(signer, address(quoteCurrency));

    function testRevertsIfIDIsWrong() public {
        ReservoirOracle.Message memory message = ReservoirOracle.Message({
            id: keccak256(
                abi.encode(
                    keccak256("ContractWideCollectionPrice(uint8 kind,uint256 twapSeconds,address contract)"),
                    ReservoirOracleUnderwriter.PriceKind.TWAP,
                    30 days,
                    nft
                )
                ),
            payload: "",
            timestamp: block.timestamp,
            signature: "" // populated below
        });

        bytes32 digest = OracleSigUtils.getTypedDataHash(message);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);

        ReservoirOracleUnderwriter.OracleInfo memory oracleInfo;
        oracleInfo.message = message;
        oracleInfo.sig = ReservoirOracleUnderwriter.Sig({v: v, r: r, s: s});

        vm.startPrank(signer);
        vm.expectRevert(ReservoirOracleUnderwriter.WrongIdentifierFromOracleMessage.selector);
        oracle.underwritePriceForCollateral(nft, ReservoirOracleUnderwriter.PriceKind.TWAP, oracleInfo, false);
    }

    function testUpdatesCachedPriceInfoIfGuardTrue() public {
        (uint40 t, uint216 p) = oracle.cachedPriceForAsset(nft);
        assertEq(t, 0);
        assertEq(p, 0);
        ReservoirOracleUnderwriter.OracleInfo memory oracleInfo = _getOracleInfoForCollateral(nft, quoteCurrency);
        oracle.underwritePriceForCollateral(ERC721(nft), priceKind, oracleInfo, true);
        (t, p) = oracle.cachedPriceForAsset(nft);
        assertEq(t, block.timestamp);
        assertEq(p, oraclePrice);
    }

    function testUpdatesToMaxPriceIfOraclePriceTooHigh() public {
        ReservoirOracleUnderwriter.OracleInfo memory oracleInfo = _getOracleInfoForCollateral(nft, quoteCurrency);
        oracle.underwritePriceForCollateral(ERC721(nft), priceKind, oracleInfo, true);
        (uint40 t, uint216 p) = oracle.cachedPriceForAsset(nft);

        uint256 passedTime = 1 days;
        vm.warp(block.timestamp + passedTime);
        uint256 maxPerSecond = 0.5e18 / uint256(1 days);
        uint256 max = p * ((maxPerSecond * passedTime) + 1e18) / 1e18;
        oraclePrice = max * 2;
        oracleInfo = _getOracleInfoForCollateral(nft, quoteCurrency);
        uint256 price = oracle.underwritePriceForCollateral(ERC721(nft), priceKind, oracleInfo, true);
        assertEq(price, max);
        (t, p) = oracle.cachedPriceForAsset(nft);
        (t, p) = oracle.cachedPriceForAsset(nft);
        assertEq(p, max);
    }

    function testMaxPriceWillNotExceedTwoDaysGrowth() public {
        ReservoirOracleUnderwriter.OracleInfo memory oracleInfo = _getOracleInfoForCollateral(nft, quoteCurrency);
        oracle.underwritePriceForCollateral(ERC721(nft), priceKind, oracleInfo, true);
        (uint40 t, uint216 p) = oracle.cachedPriceForAsset(nft);

        uint256 passedTime = 3 days;
        vm.warp(block.timestamp + passedTime);
        uint256 maxPerSecond = 0.5e18 / uint256(1 days);
        uint256 max = p * ((maxPerSecond * 2 days) + 1e18) / 1e18;
        oraclePrice = max * 2;
        oracleInfo = _getOracleInfoForCollateral(nft, quoteCurrency);
        uint256 price = oracle.underwritePriceForCollateral(ERC721(nft), priceKind, oracleInfo, true);
        assertEq(price, max);
        (t, p) = oracle.cachedPriceForAsset(nft);
        (t, p) = oracle.cachedPriceForAsset(nft);
        assertEq(p, max);
    }

    function testDoesNotUpdateCachedPriceInfoIfGuardFalse() public {
        (uint40 t, uint216 p) = oracle.cachedPriceForAsset(nft);
        assertEq(t, 0);
        assertEq(p, 0);
        ReservoirOracleUnderwriter.OracleInfo memory oracleInfo = _getOracleInfoForCollateral(nft, quoteCurrency);
        oracle.underwritePriceForCollateral(ERC721(nft), priceKind, oracleInfo, false);
        (t, p) = oracle.cachedPriceForAsset(nft);
        assertEq(t, 0);
        assertEq(p, 0);
    }

    function testReturnsPriceIfGuardDisabled() public {
        ReservoirOracleUnderwriter.OracleInfo memory oracleInfo = _getOracleInfoForCollateral(nft, quoteCurrency);
        oracle.underwritePriceForCollateral(ERC721(nft), priceKind, oracleInfo, true);
        (uint40 oldT, uint216 oldP) = oracle.cachedPriceForAsset(nft);

        uint256 passedTime = 3 days;
        vm.warp(block.timestamp + passedTime);
        uint256 maxPerSecond = 0.5e18 / uint256(1 days);
        uint256 max = oldP * ((maxPerSecond * 2 days) + 1e18) / 1e18;
        oraclePrice = max * 2;
        oracleInfo = _getOracleInfoForCollateral(nft, quoteCurrency);
        uint256 price = oracle.underwritePriceForCollateral(ERC721(nft), priceKind, oracleInfo, false);
        assertEq(price, oraclePrice);
        (uint40 t, uint216 p) = oracle.cachedPriceForAsset(nft);
        assertEq(p, oldP);
        assertEq(t, oldT);
    }
}
