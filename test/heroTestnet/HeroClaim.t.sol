pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {HeroClaim, ERC721, ERC20, MintableERC721} from "src/heroTestnet/HeroClaim.sol";
import {HeroMerkleDropHelper} from "src/heroTestnet/HeroMerkleDropHelper.sol";
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

    function testFuzz(address[5] memory members, HeroClaim.AccountClaim[5] memory claims) public {
        // will get a type error on the fixed length
        // arrays from the fuzzer so we need to copy
        // into dynamic length arrays
        address[] memory _members = new address[](5);
        HeroClaim.AccountClaim[] memory _claims = new HeroClaim.AccountClaim[](5);
        for (uint256 i = 0; i < members.length; i++) {
            _members[i] = members[i];
            _claims[i] = claims[i];
        }

        (bytes32 root, bytes32[][] memory tree) = HeroMerkleDropHelper.constructTree(_members, _claims);

        claimContract = new HeroClaim(root, phUSDC, toadz, moonBirds, dinos, blits);

        for (uint256 i = 0; i < members.length; i++) {
            address account = members[i];
            HeroClaim.AccountClaim memory claim = claims[i];

            // NFTs will revert
            vm.assume(account != address(0));
            // fuzzer sometimes give same address twice
            vm.assume(!claimContract.claimed(account));

            // give the claim contract the assets it needs to 
            // fill the claim
            _mintAllClaims(account, claim);

            bytes32[] memory proof = HeroMerkleDropHelper.createProof(i, tree);
            vm.startPrank(account);
            claimContract.claim(claim, proof);

            _checkAllClaims(account, claim);

            vm.expectRevert("claimed");
            claimContract.claim(claim, proof);
            vm.stopPrank();
        }
    }

    function _checkAllClaims(address account, HeroClaim.AccountClaim memory claim) internal {
        assertEq(phUSDC.balanceOf(account), claim.phUSDCAmount);
        assertEq(toadz.balanceOf(account), claim.toadzCount);
        assertEq(blits.balanceOf(account), claim.blitCount);
        assertEq(moonBirds.balanceOf(account), claim.moonBirdCount);
        assertEq(dinos.balanceOf(account), claim.dinoCount);
    }

    function _mintAllClaims(address account, HeroClaim.AccountClaim memory claim) internal {
        phUSDC.mint(address(claimContract), claim.phUSDCAmount);
        _mintNFT(toadz, claim.toadzCount);
        _mintNFT(blits, claim.blitCount);
        _mintNFT(moonBirds, claim.moonBirdCount);
        _mintNFT(dinos, claim.dinoCount);
    }

    function _mintNFT(MintableNFT nft, uint256 count) internal {
        for (uint256 i = 0; i < count; i++) {
            nft.mint(address(claimContract));
        }
    }
}
