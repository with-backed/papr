pragma solidity ^0.8.13;

import {ERC721} from "solmate/tokens/ERC721.sol";
import {BoringOwnable} from "@boringsolidity/BoringOwnable.sol";
import "openzeppelin-contracts/utils/Strings.sol";

contract Blitmap is ERC721("Blitmap", "PVPBLIT"), BoringOwnable {
    using Strings for uint256;

    constructor() {
        transferOwnership(msg.sender, false, false);
    }

    uint256 _nonce;

    function mint(address to) external onlyOwner {
        _mint(to, ++_nonce);
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        return string.concat("https://api.blitmap.com/v1/metadata/", id.toString());
    }
}

contract Moonbird is ERC721("Moonbird", "PVPMOON"), BoringOwnable {
    using Strings for uint256;

    constructor() {
        transferOwnership(msg.sender, false, false);
    }

    uint256 _nonce;

    function mint(address to) external onlyOwner {
        _mint(to, _nonce++);
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        return string.concat("https://live---metadata-5covpqijaa-uc.a.run.app/metadata/", id.toString());
    }
}

contract Toadz is ERC721("Toadz", "PVPTOADZ"), BoringOwnable {
    using Strings for uint256;

    constructor() {
        transferOwnership(msg.sender, false, false);
    }

    uint256 _nonce;

    function mint(address to) external onlyOwner {
        _mint(to, ++_nonce);
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        return string.concat("https://arweave.net/OVAmf1xgB6atP0uZg1U0fMd0Lw6DlsVqdvab-WTXZ1Q/", id.toString());
    }
}
