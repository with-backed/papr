// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";

import {LendingStrategy} from "src/core/LendingStrategy.sol";

contract StrategyFactory {
    struct Parameters {
        string name;
        string symbol;
        string strategyURI;
        uint256 targetAPR;
        uint256 maxLTV;
        ERC20 underlying;
    }

    Parameters public parameters;

    /// TODO we probably want maxLTV and targetAPR indexed?
    event CreateLendingStrategy(
        LendingStrategy indexed strategyAddress,
        ERC20 indexed underlying,
        string name,
        string symbol,
        string strategyURI
    );

    function newStrategy(
        string calldata name,
        string calldata symbol,
        string calldata strategyURI,
        uint256 targetAPR,
        uint256 maxLTV,
        ERC20 underlying
    )
        external
        returns (LendingStrategy)
    {
        parameters = Parameters(
            name,
            symbol,
            strategyURI,
            targetAPR,
            maxLTV,
            underlying
        );
        LendingStrategy s =
        new LendingStrategy{salt: keccak256(abi.encode(targetAPR, maxLTV, underlying))}();
        s.transferOwnership(msg.sender);

        emit CreateLendingStrategy(
            s, underlying, name, symbol, strategyURI
            );

        s.initialize();

        return s;
    }
}
