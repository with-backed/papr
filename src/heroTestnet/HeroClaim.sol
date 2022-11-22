pragma solidity ^0.8.13;

import {MerkleProof} from "openzeppelin-contracts/utils/cryptography/MerkleProof.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";

abstract contract MintableERC721 is ERC721 {
    function mint(address to) external virtual;
}

contract HeroClaim {
    mapping(address => bool) public claimed;
    bytes32 immutable merkleRoot;
    ERC20 phUSDC;
    MintableERC721 toadz;
    MintableERC721 moonBirds;
    MintableERC721 dinos;
    MintableERC721 blits;

    struct AccountClaim {
        uint224 phUSDCAmount;
        uint8 toadzCount;
        uint8 moonBirdCount;
        uint8 dinoCount;
        uint8 blitCount;
    }

    constructor(
        bytes32 _root,
        ERC20 _phUSDC,
        MintableERC721 _toadz,
        MintableERC721 _moonBirds,
        MintableERC721 _dinos,
        MintableERC721 _blits
    ) {
        merkleRoot = _root;
        phUSDC = _phUSDC;
        toadz = _toadz;
        moonBirds = _moonBirds;
        dinos = _dinos;
        blits = _blits;
    }

    function claim(AccountClaim calldata claim, bytes32[] calldata merkleProof) public {
        require(!claimed[msg.sender], "claimed");

        bytes32 node = ~keccak256(abi.encode(msg.sender, claim));

        require(MerkleProof.verifyCalldata(merkleProof, merkleRoot, node), "MerkleDistributor: Invalid proof.");

        claimed[msg.sender] = true;

        if (claim.phUSDCAmount > 0) phUSDC.transfer(msg.sender, claim.phUSDCAmount);
        _mint(msg.sender, claim.toadzCount, toadz);
        _mint(msg.sender, claim.moonBirdCount, moonBirds);
        _mint(msg.sender, claim.dinoCount, dinos);
        _mint(msg.sender, claim.blitCount, blits);
    }

    function _mint(address to, uint256 count, MintableERC721 nft) internal {
        for (uint256 i = 0; i < count; i++) {
            nft.mint(to);
        }
    }
}
