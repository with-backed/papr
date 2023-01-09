// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";

import {ReservoirOracle} from "@reservoir/ReservoirOracle.sol";
import {ReservoirOracleUnderwriter} from "../../src/ReservoirOracleUnderwriter.sol";
import {IPaprController} from "../../src/interfaces/IPaprController.sol";
import {OracleSigUtils} from "../OracleSigUtils.sol";

contract OracleTest is Test {
    uint256 oraclePrice = 3e6;

    uint256 timestamp;
    uint256 internal oraclePrivateKey = 0xA11CE;
    address oracleAddress = vm.addr(oraclePrivateKey);
    ReservoirOracleUnderwriter.PriceKind priceKind = ReservoirOracleUnderwriter.PriceKind.LOWER;

    function _getOracleInfoForCollateral(ERC721 collateral, ERC20 underlying)
        internal
        returns (ReservoirOracleUnderwriter.OracleInfo memory oracleInfo)
    {
        ReservoirOracle.Message memory message = ReservoirOracle.Message({
            id: _constructOracleId(collateral),
            payload: abi.encode(underlying, oraclePrice),
            timestamp: timestamp == 0 ? block.timestamp : timestamp,
            signature: "" // populated ourselves on the OracleInfo.Sig struct
        });

        bytes32 digest = OracleSigUtils.getTypedDataHash(message);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(oraclePrivateKey, digest);

        oracleInfo.message = message;
        oracleInfo.sig = ReservoirOracleUnderwriter.Sig({v: v, r: r, s: s});
    }

    function _constructOracleId(ERC721 collectionAddress) internal returns (bytes32 id) {
        id = keccak256(
            abi.encode(
                keccak256("ContractWideCollectionPrice(uint8 kind,uint256 twapSeconds,address contract)"),
                priceKind,
                30 days,
                collectionAddress
            )
        );
    }
}
