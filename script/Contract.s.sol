// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";

import {DebtToken} from "src/core/DebtToken.sol";
import {StrategyFactory} from "src/core/StrategyFactory.sol";
import {LendingStrategy} from "src/core/LendingStrategy.sol";

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

    function tokenURI(uint256 id)
        public
        view
        override
        returns (string memory)
    {}
}

contract ContractScript is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        address deployer = 0xE89CB2053A04Daf86ABaa1f4bC6D50744e57d39E;

        address collateral = 0xb7D7fe7995D1E347916fAae8e16CFd6dD21a9bAE;
        address underlying = 0x3089B47853df1b82877bEef6D904a0ce98a12553;

        StrategyFactory s = new StrategyFactory();
        LendingStrategy strategy = s.newStrategy(
            "APE Loans",
            "AP",
            "uri",
            2e17,
            5e17,
            ERC20(underlying)
        );

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
