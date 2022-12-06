// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";

import {CreatorGuarded} from "src/base/CreatorGuarded.sol";

contract PaprToken is ERC20, CreatorGuarded {
    address immutable creator;

    constructor(string memory name, string memory symbol)
        ERC20(string.concat("papr ", name), string.concat("papr", symbol), 18)
    {
        creator = msg.sender;
    }

    function mint(address to, uint256 amount) external onlyCreator {
        _mint(to, amount);
    }

    function burn(address account, uint256 amount) external onlyCreator {
        _burn(account, amount);
    }
}
