// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ReservoirOracle} from "@reservoir/ReservoirOracle.sol";
import {IUnderwriter} from "src/interfaces/IUnderwriter.sol";

contract ReservoirOracleUnderwriter is IUnderwriter {
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

    uint256 constant TWAP_MINUTES = 30 days / 60;
    address public immutable oracleSigner;
    address public immutable quoteCurrency;

    error IncorrectOracleSigner();
    error WrongCollateralFromOracleMessage();
    error WrongCurrencyFromOracleMessage();

    constructor(address _oracleSigner, address _quoteCurrency) {
        oracleSigner = _oracleSigner;
        quoteCurrency = _quoteCurrency;
    }

    function underwritePriceForCollateral(
        uint256 tokenId,
        address contractAddress,
        bytes memory data
    ) public override returns (uint256) {
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
                keccak256("ContractWideCollectionPrice(uint8 kind,uint256 twapMinutes,address contract)"),
                PriceKind.LOWER,
                TWAP_MINUTES,
                contractAddress
            )
        );

        if (oracleInfo.message.id != expectedId) {
            revert WrongCollateralFromOracleMessage();
        }

        (address oracleQuoteCurrency, uint256 oraclePrice) =
            abi.decode(oracleInfo.message.payload, (address, uint256));
        if (oracleQuoteCurrency != quoteCurrency) {
            revert WrongCurrencyFromOracleMessage();
        }

        return oraclePrice;
    }
}
