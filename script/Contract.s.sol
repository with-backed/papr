// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";

import {DebtToken} from "src/DebtToken.sol";
import {Oracle} from "src/squeeth/Oracle.sol";
import {StrategyFactory} from "src/StrategyFactory.sol";

contract TestERC20 is ERC20("USDC", "USDC", 18) {
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract TestERC721 is ERC721("Fake Bored Apes", "fAPE") {
    uint256 _nonce; 
    function mint(address to) external {
        _mint(to, ++_nonce);
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
    }
}

contract ContractScript is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        // new TestERC20();
        // new TestERC721();
        new StrategyFactory();
    }
}
