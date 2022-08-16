// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC721} from "solmate/tokens/ERC721.sol";

import {CreatorGuarded} from "./CreatorGuarded.sol";

contract DebtVault is ERC721, CreatorGuarded {

    constructor(string memory strategy, string memory symbol)
        ERC721(
            string.concat(strategy, "debt vault"),
            string.concat("dv", symbol)
        )
    {
        creator = msg.sender;
    }

    function mint(address to, uint256 id) external onlyCreator() {
        _safeMint(to, id, "");
    }

    function burn(uint256 id) external onlyCreator() {
        _burn(id);
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        
    }
}