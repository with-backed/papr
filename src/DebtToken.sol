// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";

import {CreatorGuarded} from "./CreatorGuarded.sol";

contract DebtToken is ERC20 {
    address creator;

    constructor(string memory strategy, string memory symbol)
        ERC20(
            string.concat(strategy, "debt token"),
            string.concat("dt", symbol),
            18
        )
    {
        creator = msg.sender;
    }

    function mint(address to, uint256 amount) external {
        if (msg.sender != creator) {
            revert("wrong");
        }

        _mint(to, amount);
    }

    function burn(address account, uint256 amount) external {
        if (msg.sender != creator) {
            revert("wrong");
        }

        _burn(account, amount);
    }
}
