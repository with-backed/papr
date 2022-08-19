// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";

import {Oracle} from "src/squeeth/Oracle.sol";
import {LendingStrategy} from "src/LendingStrategy.sol";

contract StrategyFactory {
    Oracle public oracle;

    constructor() {
        oracle = new Oracle();
    }

    event LendingStrategyCreated(address indexed strategyAddress, address indexed collateral, address indexed underlying, string name, string symbol);

    function newStrategy(
        string memory name,
        string memory symbol,
        ERC721 collateral,
        ERC20 underlying
    ) external returns (LendingStrategy) {
        LendingStrategy s = new LendingStrategy(
            name,
            symbol,
            collateral,
            underlying,
            oracle
        );

        emit LendingStrategyCreated(address(s), address(collateral), address(underlying), name, symbol);

        return s;
    }
}