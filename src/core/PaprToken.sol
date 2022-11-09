// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";

import {CreatorGuarded} from "src/core/base/CreatorGuarded.sol";

contract PaprToken is ERC20 {
    address immutable creator;

    constructor(string memory strategy, string memory symbol, string memory underlyingSymbol)
        ERC20(string.concat("pAPR ", strategy), string.concat("pAPR", symbol, "_", underlyingSymbol), 18)
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
