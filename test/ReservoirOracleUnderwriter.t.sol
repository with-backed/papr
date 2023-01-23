// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Test.sol";

import {ReservoirOracle} from "@reservoir/ReservoirOracle.sol";

import {ReservoirOracleUnderwriter, ERC721} from "../src/ReservoirOracleUnderwriter.sol";
import {OracleSigUtils} from "./OracleSigUtils.sol";

contract ReservoirOracleUnderwriterTest is Test {
    uint256 signerPrivateKey = 0xA11CE;
    address signer = vm.addr(signerPrivateKey);
    ReservoirOracleUnderwriter oracle = new ReservoirOracleUnderwriter(signer, address(2));

    function testRevertsIfIDIsWrong() public {
        address nft = address(3);
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
        oracle.underwritePriceForCollateral(ERC721(nft), ReservoirOracleUnderwriter.PriceKind.TWAP, oracleInfo);
    }
}
