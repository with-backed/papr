// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";

import {ILendingStrategy} from "src/interfaces/ILendingStrategy.sol";
import {ReservoirOracleUnderwriter} from "src/core/ReservoirOracleUnderwriter.sol";
import {DebtToken} from "src/core/DebtToken.sol";
import {LendingStrategy} from "src/core/LendingStrategy.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";

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

contract ContractScript is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        address deployer = 0xE89CB2053A04Daf86ABaa1f4bC6D50744e57d39E;

        address underlying = 0x3089B47853df1b82877bEef6D904a0ce98a12553;

        LendingStrategy strategy = new LendingStrategy(
            "PUNKs Loans",
            "PL",
            5e17,
            2e18,
            0.8e18,
            ERC20(underlying),
            deployer
        );
        strategy.claimOwnership();

        ILendingStrategy.SetAllowedCollateralArg[] memory args = new ILendingStrategy.SetAllowedCollateralArg[](3);
        args[0] =
            ILendingStrategy.SetAllowedCollateralArg({addr: 0xb7D7fe7995D1E347916fAae8e16CFd6dD21a9bAE, allowed: true});
        args[1] =
            ILendingStrategy.SetAllowedCollateralArg({addr: 0x6EF2C9CB23F03014d18d7E4CeEAeC497dB00247C, allowed: true});
        args[2] =
            ILendingStrategy.SetAllowedCollateralArg({addr: 0x8232c5Fd480C2a74d2f25d3362f262fF3511CE49, allowed: true});

        strategy.setAllowedCollateral(args);

        // uint256 tokenId = 17;

        // OpenVaultRequest memory request = OpenVaultRequest(
        //     address(this),
        //     1e18,
        //     Collateral({nft: ERC721(collateral), id: tokenId}),
        //     OracleInfo({price: 3e18, period: OracleInfoPeriod.SevenDays}),
        //     Sig({v: 1, r: keccak256("x"), s: keccak256("x")})
        // );

        // ERC721(collateral).safeTransferFrom(
        //     address(this),
        //     address(strategy),
        //     tokenId,
        //     abi.encode(request)
        // );

        vm.stopBroadcast();
    }
}
