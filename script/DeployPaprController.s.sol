// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";

import {IPaprController} from "src/interfaces/IPaprController.sol";
import {PaprController} from "src/PaprController.sol";
import "openzeppelin-contracts/utils/Strings.sol";
import {Base} from "script/actions/Base.s.sol";

contract DeployPaprController is Base {
    // WETH
    ERC20 underlying = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        ERC721[] memory collateral = new ERC721[](10);
        // dickbutts
        collateral[0] = ERC721(0x42069ABFE407C60cf4ae4112bEDEaD391dBa1cdB);
        // penguins
        collateral[1] = ERC721(0xBd3531dA5CF5857e7CfAA92426877b022e612cf8);
        // mfers
        collateral[2] = ERC721(0x79FCDEF22feeD20eDDacbB2587640e45491b757f);
        // tubby cats
        collateral[3] = ERC721(0xCa7cA7BcC765F77339bE2d648BA53ce9c8a262bD);
        // wizards
        collateral[4] = ERC721(0x521f9C7505005CFA19A8E5786a9c3c9c9F5e6f42);
        // cool cats
        collateral[5] = ERC721(0x1A92f7381B9F03921564a437210bB9396471050C);
        // beanz 
        collateral[6] = ERC721(0x306b1ea3ecdf94aB739F1910bbda052Ed4A9f949);
        // loot 
        collateral[7] = ERC721(0xFF9C1b15B16263C61d017ee9F65C50e4AE0113D7);
        // toadz
        collateral[8] = ERC721(0x1CB1A5e65610AEFF2551A50f76a87a7d3fB649C6);
        // milady
        collateral[9] = ERC721(0x5Af0D9827E0c53E4799BB226655A1de152A425a5);

        controller = new PaprController(
            "meme",
            "MEME",
            5e17,
            underlying,
            deployer,
            collateral
        );

        address admin = 0x6aFFF2C21676a9790390a0f7518adC59B849B7c7;

        controller.transferOwnership(admin);

        vm.stopBroadcast();
    }
}

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

    function tokenURI(uint256 id) public view override returns (string memory) {}
}

contract Mfers is ERC721("mfer", "MFER") {
    using Strings for uint256;

    uint256 _nonce;

    function mint(address to) external {
        _mint(to, ++_nonce);
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        return string.concat("ipfs://QmWiQE65tmpYzcokCheQmng2DCM33DEhjXcPB6PanwpAZo/", id.toString());
    }
}

contract TubbyCats is ERC721("Tubby Cats", "TUBBY") {
    using Strings for uint256;

    uint256 _nonce;

    function mint(address to) external {
        _mint(to, ++_nonce);
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        return string.concat("ipfs://QmeN7ZdrTGpbGoo8URqzvyiDtcgJxwoxULbQowaTGhTeZc/", (5489 + id).toString());
    }
}

contract AllStarz is ERC721("Allstarz", "ALLSTAR") {
    using Strings for uint256;

    uint256 _nonce;

    function mint(address to) external {
        _mint(to, ++_nonce);
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        return string.concat("ipfs://bafybeifsek6gt7c5ua7kkf6thxbpmj2adlsptsiwbfiohzdkjyxxcv2aje/", id.toString());
    }
}

contract CoolCats is ERC721("Cool Cats", "COOL") {
    using Strings for uint256;

    uint256 _nonce;

    function mint(address to) external {
        _mint(to, ++_nonce);
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        return string.concat("https://api.coolcatsnft.com/cat/", id.toString());
    }
}

contract Phunks is ERC721("CryptoPhunksV2", "PHUNK") {
    using Strings for uint256;

    uint256 _nonce;

    function mint(address to) external {
        _mint(to, ++_nonce);
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        return string.concat(
            "https://gateway.pinata.cloud/ipfs/QmcfS3bYBErM2zo3dSRLbFzr2bvitAVJCMh5vmDf3N3B9X", id.toString()
        );
    }
}
