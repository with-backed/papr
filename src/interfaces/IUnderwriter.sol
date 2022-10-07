// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ReservoirOracle} from "@reservoir/ReservoirOracle.sol";

interface IUnderwriter {
    struct Sig {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    struct OracleInfo {
        ReservoirOracle.Message message;
        Sig sig;
    }

    function underwritePriceForCollateral(
        uint256 tokenId,
        address contractAddress,
        bytes memory data
    ) external returns (uint256);

    error IncorrectOracleSigner();
    error InvalidOracleMessage();
}
