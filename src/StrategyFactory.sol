// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";

import {Oracle} from "src/squeeth/Oracle.sol";
import {LendingStrategy} from "src/LendingStrategy.sol";

contract StrategyFactory {
    Oracle public oracle;

    constructor() {
        oracle = new Oracle();
    }

    event NewStrategy(LendingStrategy indexed strategy);

    function newStrategy(
        string memory name,
        string memory symbol,
        ERC20 underlying
    ) external returns (LendingStrategy) {
        LendingStrategy s = new LendingStrategy(
            name,
            symbol,
            underlying,
            oracle
        );

        emit NewStrategy(s);

        return s;
    }
}