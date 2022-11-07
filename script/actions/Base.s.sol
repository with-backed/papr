// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {ReservoirOracleUnderwriter, ReservoirOracle} from "src/core/ReservoirOracleUnderwriter.sol";

import {LendingStrategy} from "src/core/LendingStrategy.sol";
import {OracleSigUtils} from "test/OracleSigUtils.sol";

contract Base is Script {
    LendingStrategy strategy = LendingStrategy(vm.envAddress("STRATEGY"));
    uint256 pk = vm.envUint("PRIVATE_KEY");
    address deployer = vm.addr(pk);
    ReservoirOracleUnderwriter.PriceKind oraclePriceKind = ReservoirOracleUnderwriter.PriceKind.LOWER;

    function _constructOracleId(address collectionAddress) internal returns (bytes32 id) {
        id = keccak256(
            abi.encode(
                keccak256("ContractWideCollectionPrice(uint8 kind,uint256 twapMinutes,address contract)"),
                oraclePriceKind,
                30 days / 60,
                collectionAddress
            )
        );
    }

    function _getOracleInfoForCollateral(address collateral, uint256 price)
        internal
        returns (ReservoirOracleUnderwriter.OracleInfo memory oracleInfo)
    {
        ReservoirOracle.Message memory message = ReservoirOracle.Message({
            id: _constructOracleId(collateral),
            payload: abi.encode(strategy.underlying(), price),
            timestamp: block.timestamp,
            signature: "" // populated ourselves on the OracleInfo.Sig struct
        });

        bytes32 digest = OracleSigUtils.getTypedDataHash(message);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);

        oracleInfo.message = message;
        oracleInfo.sig = ReservoirOracleUnderwriter.Sig({v: v, r: r, s: s});
    }
}
