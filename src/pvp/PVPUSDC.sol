pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {BoringOwnable} from "@boringsolidity/BoringOwnable.sol";

contract PVPUSDC is ERC20("Backed PVP USDC", "PVPUSDC", 6), BoringOwnable {
    address staker;
    modifier onlyOwnerOrStaker() {
        require(
            msg.sender == staker || msg.sender == owner,
            "Ownable: caller is not the owner"
        );
        _;
    }

    constructor() {
        transferOwnership(msg.sender, false, false);
    }

    function setStaker(address _staker) external onlyOwner {
        staker = _staker;
    }

    function mint(address to, uint256 amount) external onlyOwnerOrStaker {
        _mint(to, amount);
    }
}
