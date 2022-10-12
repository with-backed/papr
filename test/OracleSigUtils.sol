// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ReservoirOracle} from "@reservoir/ReservoirOracle.sol";

contract OracleSigUtils {
    bytes32 internal DOMAIN_SEPARATOR;

    bytes32 public constant MESSAGE_TYPEHASH = keccak256("Message(bytes32 id,bytes payload,uint256 timestamp)");

    function getStructHash(ReservoirOracle.Message memory message) internal pure returns (bytes32) {
        return keccak256(abi.encode(MESSAGE_TYPEHASH, message.id, keccak256(message.payload), message.timestamp));
    }

    function getTypedDataHash(ReservoirOracle.Message memory message) public view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", getStructHash(message)));
    }
}
