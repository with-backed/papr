pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {HeroClaim, ERC721, ERC20, MintableERC721} from "src/heroTestnet/HeroClaim.sol";
import {TestERC20} from "test/mocks/TestERC20.sol";

contract MintableNFT is MintableERC721 {
    uint256 _nonce;

    constructor() ERC721("TEST", "TEST") {}

    function mint(address to) external override {
        _mint(to, ++_nonce);
    }

    function tokenURI(uint256 id) public view override returns (string memory) {}
}

contract HeroClaimTest is Test {
    HeroClaim claimContract;
    MintableNFT toadz = new MintableNFT();
    MintableNFT blits = new MintableNFT();
    MintableNFT moonBirds = new MintableNFT();
    MintableNFT dinos = new MintableNFT();
    TestERC20 phUSDC = new TestERC20();

    function testFuzz(address[20] memory members, HeroClaim.AccountClaim[20] memory claims) public {
        vm.assume(members[0] != address(0));
        address[] memory _members = new address[](1);
        HeroClaim.AccountClaim[] memory _claims = new HeroClaim.AccountClaim[](1);
        for (uint256 i = 0; i < 1; i++) {
            _members[i] = members[i];
            _claims[i] = claims[i];
        }
        (bytes32 root, bytes32[][] memory tree) = MerkleDropHelper.constructTree(_members, _claims);
        claimContract = new HeroClaim(root, phUSDC, toadz, moonBirds, dinos, blits);
        for (uint256 i = 0; i < 1; i++) {
            phUSDC.mint(address(claimContract), claims[i].phUSDCAmount);
            _mint(toadz, claims[i].toadzCount);
            _mint(blits, claims[i].blitCount);
            _mint(moonBirds, claims[i].moonBirdCount);
            _mint(dinos, claims[i].dinoCount);
            vm.startPrank(members[0]);
            claimContract.claim(claims[0], MerkleDropHelper.createProof(0, tree));
            assertEq(phUSDC.balanceOf(members[i]), claims[i].phUSDCAmount);
            assertEq(toadz.balanceOf(members[i]), claims[i].toadzCount);
            assertEq(blits.balanceOf(members[i]), claims[i].blitCount);
            assertEq(moonBirds.balanceOf(members[i]), claims[i].moonBirdCount);
            assertEq(dinos.balanceOf(members[i]), claims[i].dinoCount);
        }
    }

    function _mint(MintableNFT nft, uint256 count) internal {
        for (uint256 i = 0; i < count; i++) {
            nft.mint(address(claimContract));
        }
    }

    function prove(bytes32 leaf, bytes32[] memory siblings) public view returns (bytes32) {
        // In a sparse tree, empty leaves have a value of 0, so don't allow 0 as input.
        require(leaf != 0, "invalid leaf value");
        bytes32 node = leaf;
        for (uint256 i = 0; i < siblings.length; ++i) {
            bytes32 sibling = siblings[i];
            node = keccak256(
                // Siblings are always hashed in sorted order.
                node > sibling ? abi.encode(sibling, node) : abi.encode(node, sibling)
            );
        }
        return node;
    }
}

/// from https://github.com/dragonfly-xyz/useful-solidity-patterns/blob/main/patterns/merkle-proofs/MerkleProofs.sol#L54
/// with modifications
library MerkleDropHelper {
    // Construct a sparse merkle tree from a list of members and respective claim
    // amounts. This tree will be sparse in the sense that rather than padding
    // tree levels to the next power of 2, missing nodes will default to a value of
    // 0.
    function constructTree(address[] memory members, HeroClaim.AccountClaim[] memory claims)
        external
        pure
        returns (bytes32 root, bytes32[][] memory tree)
    {
        require(members.length != 0 && members.length == claims.length);
        // Determine tree height.
        uint256 height = 0;
        {
            uint256 n = members.length;
            while (n != 0) {
                n = n == 1 ? 0 : (n + 1) / 2;
                ++height;
            }
        }
        tree = new bytes32[][](height);
        // The first layer of the tree contains the leaf nodes, which are
        // hashes of each member and claim amount.
        bytes32[] memory nodes = tree[0] = new bytes32[](members.length);
        for (uint256 i = 0; i < members.length; ++i) {
            // Leaf hashes are inverted to prevent second preimage attacks.
            nodes[i] = ~keccak256(abi.encode(members[i], claims[i]));
        }
        // Build up subsequent layers until we arrive at the root hash.
        // Each parent node is the hash of the two children below it.
        // E.g.,
        //              H0         <-- root (layer 2)
        //           /     \
        //        H1        H2
        //      /   \      /  \
        //    L1     L2  L3    L4  <--- leaves (layer 0)
        for (uint256 h = 1; h < height; ++h) {
            uint256 nHashes = (nodes.length + 1) / 2;
            bytes32[] memory hashes = new bytes32[](nHashes);
            for (uint256 i = 0; i < nodes.length; i += 2) {
                bytes32 a = nodes[i];
                // Tree is sparse. Missing nodes will have a value of 0.
                bytes32 b = i + 1 < nodes.length ? nodes[i + 1] : bytes32(0);
                // Siblings are always hashed in sorted order.
                hashes[i / 2] = keccak256(a > b ? abi.encode(b, a) : abi.encode(a, b));
            }
            tree[h] = nodes = hashes;
        }
        // Note the tree root is at the bottom.
        root = tree[height - 1][0];
    }

    // Given a merkle tree and a member index (leaf node index), generate a proof.
    // The proof is simply the list of sibling nodes/hashes leading up to the root.
    function createProof(uint256 memberIndex, bytes32[][] memory tree) external pure returns (bytes32[] memory proof) {
        uint256 leafIndex = memberIndex;
        uint256 height = tree.length;
        proof = new bytes32[](height - 1);
        for (uint256 h = 0; h < proof.length; ++h) {
            uint256 siblingIndex = leafIndex % 2 == 0 ? leafIndex + 1 : leafIndex - 1;
            if (siblingIndex < tree[h].length) {
                proof[h] = tree[h][siblingIndex];
            }
            leafIndex /= 2;
        }
    }
}
