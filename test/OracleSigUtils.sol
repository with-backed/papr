// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { ILendingStrategy } from "src/interfaces/ILendingStrategy.sol";

contract OracleSigUtils {
    bytes32 internal DOMAIN_SEPARATOR;

    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant MESSAGE_TYPEHASH =
        keccak256("Message(bytes32 id,bytes payload,uint256 timestamp)");

    // computes the hash of a permit
    function getStructHash(ILendingStrategy.OracleMessage memory message)
        internal
        pure
        returns (bytes32)
    {
        return
            keccak256(
                abi.encode(
                    MESSAGE_TYPEHASH,
                    message.id,
                    message.payload,
                    message.timestamp
                )
            );
    }

    // computes the hash of the fully encoded EIP-712 message for the domain, which can be used to recover the signer
    function getTypedDataHash(ILendingStrategy.OracleMessage memory message)
        public
        view
        returns (bytes32)
    {
        return
            keccak256(
                abi.encodePacked(
                    "\x19Ethereum Signed Message:\n32",
                    getStructHash(message)
                )
            );
    }
}