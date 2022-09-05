// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";

contract TestERC20 is ERC20("TEST", "TEST,", 18) {
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
