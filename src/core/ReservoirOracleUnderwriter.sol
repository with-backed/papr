// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ReservoirOracle} from "@reservoir/ReservoirOracle.sol";
import {IUnderwriter} from "src/interfaces/IUnderwriter.sol";

contract ReservoirOracleUnderwriter is IUnderwriter {
    struct Sig {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    struct OracleInfo {
        ReservoirOracle.Message message;
        Sig sig;
    }

    address public oracleSigner;

    error IncorrectOracleSigner();
    error InvalidOracleMessage();

    constructor(address _oracleSigner) {
        oracleSigner = _oracleSigner;
    }

    function underwritePriceForCollateral(uint256 tokenId, address contractAddress, bytes memory data)
        external
        override
        returns (uint256)
    {
        OracleInfo memory oracleInfo = abi.decode(data, (OracleInfo));
        address signerAddress = ecrecover(
            keccak256(
                abi.encodePacked(
                    "\x19Ethereum Signed Message:\n32",
                    // EIP-712 structured-data hash
                    keccak256(
                        abi.encode(
                            keccak256("Message(bytes32 id,bytes payload,uint256 timestamp)"),
                            oracleInfo.message.id,
                            oracleInfo.message.payload,
                            oracleInfo.message.timestamp
                        )
                    )
                )
            ),
            oracleInfo.sig.v,
            oracleInfo.sig.r,
            oracleInfo.sig.s
        );

        // Ensure the signer matches the designated oracle address
        if (signerAddress != oracleSigner) {
            revert IncorrectOracleSigner();
        }

        bytes32 expectedId = keccak256(
            abi.encode(
                keccak256("ContractWideCollectionPrice(uint8 kind,uint256 twapMinutes,address contract)"),
                1,
                30 days / 60, // minutes in a month
                contractAddress
            )
        );

        if (oracleInfo.message.id != expectedId) {
            revert InvalidOracleMessage();
        }

        (, uint256 oraclePrice) = abi.decode(oracleInfo.message.payload, (address, uint256));
        return oraclePrice;
    }
}
