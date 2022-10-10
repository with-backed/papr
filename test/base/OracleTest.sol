// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {ReservoirOracle} from "@reservoir/ReservoirOracle.sol";
import {ReservoirOracleUnderwriter} from "src/core/ReservoirOracleUnderwriter.sol";
import {IUnderwriter} from "src/interfaces/IUnderwriter.sol";
import {ILendingStrategy} from "src/interfaces/ILendingStrategy.sol";
import {OracleSigUtils} from "test/OracleSigUtils.sol";

contract OracleTest is Test {
    uint128 oraclePrice = 3e18;

    uint256 internal oraclePrivateKey = 0xA11CE;
    OracleSigUtils internal sigUtils = new OracleSigUtils();
    address oracleAddress = vm.addr(oraclePrivateKey);

    function _getOracleInfoForCollateral(address collateral, address underlying)
        internal
        returns (ReservoirOracleUnderwriter.OracleInfo memory oracleInfo)
    {
        ReservoirOracle.Message memory message = ReservoirOracle.Message({
            id: _constructOracleId(collateral),
            payload: abi.encode(underlying, oraclePrice),
            timestamp: block.timestamp,
            signature: "" // populated ourselves on the OracleInfo.Sig struct
        });

        bytes32 digest = sigUtils.getTypedDataHash(message);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(oraclePrivateKey, digest);

        oracleInfo.message = message;
        oracleInfo.sig = ReservoirOracleUnderwriter.Sig({v: v, r: r, s: s});
    }

    function _constructOracleId(address collectionAddress) internal returns (bytes32 id) {
        id = keccak256(
            abi.encode(
                keccak256("ContractWideCollectionPrice(uint8 kind,uint256 twapMinutes,address contract)"),
                1,
                30 days / 60,
                collectionAddress
            )
        );
    }
}
