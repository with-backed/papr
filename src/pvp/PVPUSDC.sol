pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {BoringOwnable} from "@boringsolidity/BoringOwnable.sol";

contract PVPUSDC is ERC20("Backed PVP USDC", "PVPUSDC", 6), BoringOwnable {
    constructor() {
        transferOwnership(msg.sender, false, false);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
