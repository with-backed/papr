// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import {ReservoirOracleUnderwriter, ReservoirOracle} from "src/ReservoirOracleUnderwriter.sol";
import {PaprController} from "src/PaprController.sol";
import {OracleSigUtils} from "test/OracleSigUtils.sol";

contract Base is Script {
    PaprController controller = PaprController(vm.envAddress("CONTROLLER"));
    uint256 pk = vm.envUint("PRIVATE_KEY");
    address deployer = vm.addr(pk);
    ReservoirOracleUnderwriter.PriceKind oraclePriceKind = ReservoirOracleUnderwriter.PriceKind.LOWER;

    function _constructOracleId(address collectionAddress) internal returns (bytes32 id) {
        id = keccak256(
            abi.encode(
                keccak256("ContractWideCollectionTopBidPrice(uint8 kind,uint256 twapSeconds,address contract)"),
                oraclePriceKind,
                30 days,
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
            payload: abi.encode(controller.underlying(), price),
            timestamp: block.timestamp,
            signature: "" // populated ourselves on the OracleInfo.Sig struct
        });

        bytes32 digest = OracleSigUtils.getTypedDataHash(message);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);

        oracleInfo.message = message;
        oracleInfo.sig = ReservoirOracleUnderwriter.Sig({v: v, r: r, s: s});
    }
}
