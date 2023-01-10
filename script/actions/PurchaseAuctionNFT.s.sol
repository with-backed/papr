// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.17;

// import "forge-std/Script.sol";
// import {ERC721} from "solmate/tokens/ERC721.sol";
// import {INFTEDA} from "src/NFTEDA/extensions/NFTEDAStarterIncentive.sol";

// import {Base} from "script/actions/Base.s.sol";
// import {IPaprController} from "src/interfaces/IPaprController.sol";
// import {ReservoirOracleUnderwriter} from "src/ReservoirOracleUnderwriter.sol";

// contract PurchaseAuctionNFT is Base {
//     function run() public {
//         INFTEDA.Auction memory auction = INFTEDA.Auction({
//             nftOwner: deployer,
//             auctionAssetID: 21,
//             auctionAssetContract: ERC721(0x8232c5Fd480C2a74d2f25d3362f262fF3511CE49),
//             perPeriodDecayPercentWad: 700000000000000000,
//             secondsInPeriod: 86400,
//             startPrice: 2999999994047916656,
//             paymentAsset: controller.papr()
//         });
//         uint256 price = controller.auctionCurrentPrice(auction);
//         oraclePriceKind = ReservoirOracleUnderwriter.PriceKind.TWAP;
//         vm.startBroadcast();
//         controller.purchaseLiquidationAuctionNFT(
//             auction, price, deployer, _getOracleInfoForCollateral(address(auction.auctionAssetContract), 3e20)
//         );
//     }
// }
