// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";
import {INFTEDA} from "NFTEDA/extensions/NFTEDAStarterIncentive.sol";

import {Base} from "script/actions/Base.s.sol";
import {ILendingStrategy} from "src/interfaces/ILendingStrategy.sol";

contract PurchaseAuctionNFT is Base {
    function run() public {
        INFTEDA.Auction memory auction = INFTEDA.Auction({
            nftOwner: deployer,
            auctionAssetID: 19,
            auctionAssetContract: ERC721(0x8232c5Fd480C2a74d2f25d3362f262fF3511CE49),
            perPeriodDecayPercentWad: 700000000000000000,
            secondsInPeriod: 86400,
            startPrice: 899999835722514446763,
            paymentAsset: strategy.perpetual()
        });
        uint256 price = strategy.auctionCurrentPrice(auction);
        vm.startBroadcast();
        strategy.purchaseLiquidationAuctionNFT(auction, price, deployer);
    }
}
