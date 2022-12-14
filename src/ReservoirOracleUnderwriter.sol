// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ERC721} from "solmate/tokens/ERC721.sol";
import {ReservoirOracle} from "@reservoir/ReservoirOracle.sol";

contract ReservoirOracleUnderwriter {
    enum PriceKind {
        SPOT,
        TWAP,
        LOWER,
        UPPER
    }

    struct Sig {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    struct OracleInfo {
        ReservoirOracle.Message message;
        Sig sig;
    }

    uint256 constant TWAP_SECONDS = 30 days;
    uint256 constant VALID_FOR = 20 minutes;
    address public immutable oracleSigner;
    address public immutable quoteCurrency;

    error IncorrectOracleSigner();
    error WrongIdentifierFromOracleMessage();
    error WrongCurrencyFromOracleMessage();
    error OracleMessageTooOld();

    constructor(address _oracleSigner, address _quoteCurrency) {
        oracleSigner = _oracleSigner;
        quoteCurrency = _quoteCurrency;
    }

    function underwritePriceForCollateral(ERC721 asset, PriceKind priceKind, OracleInfo memory oracleInfo)
        public
        returns (uint256)
    {
        address signerAddress = ecrecover(
            keccak256(
                abi.encodePacked(
                    "\x19Ethereum Signed Message:\n32",
                    // EIP-712 structured-data hash
                    keccak256(
                        abi.encode(
                            keccak256("Message(bytes32 id,bytes payload,uint256 timestamp)"),
                            oracleInfo.message.id,
                            keccak256(oracleInfo.message.payload),
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
                keccak256("ContractWideCollectionPrice(uint8 kind,uint256 twapSeconds,address contract)"),
                priceKind,
                TWAP_SECONDS,
                asset
            )
        );

        if (oracleInfo.message.id != expectedId) {
            revert WrongIdentifierFromOracleMessage();
        }

        if (
            oracleInfo.message.timestamp > block.timestamp || oracleInfo.message.timestamp + VALID_FOR < block.timestamp
        ) {
            revert OracleMessageTooOld();
        }

        (address oracleQuoteCurrency, uint256 oraclePrice) = abi.decode(oracleInfo.message.payload, (address, uint256));
        if (oracleQuoteCurrency != quoteCurrency) {
            revert WrongCurrencyFromOracleMessage();
        }

        return oraclePrice;
    }
}
