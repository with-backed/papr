// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";

import {Oracle} from "src/squeeth/Oracle.sol";
import {LendingStrategy} from "src/core/LendingStrategy.sol";

contract StrategyFactory {
    struct Parameters {
        string name;
        string symbol;
        bytes32 allowedCollateralRoot;
        uint256 targetAPR;
        uint256 maxLTV;
        ERC20 underlying;
    }

    Parameters public parameters;

    /// TODO we probably want maxLTV and targetAPR indexed?
    event LendingStrategyCreated(
        LendingStrategy indexed strategyAddress,
        bytes32 indexed allowedCollateralRoot,
        ERC20 indexed underlying,
        string name,
        string symbol
    );

    function newStrategy(
        string calldata name,
        string calldata symbol,
        bytes32 allowedCollateralRoot,
        uint256 targetAPR,
        uint256 maxLTV,
        ERC20 underlying
    )
        external
        returns (LendingStrategy)
    {
        parameters = Parameters(
            name, symbol, allowedCollateralRoot, targetAPR, maxLTV, underlying
        );
        LendingStrategy s =
        new LendingStrategy{salt: keccak256(abi.encode(allowedCollateralRoot, targetAPR, maxLTV, underlying))}();

        emit LendingStrategyCreated(
            s, allowedCollateralRoot, underlying, name, symbol
            );

        return s;
    }
}
