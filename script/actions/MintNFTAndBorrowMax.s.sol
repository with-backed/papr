// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";
import {TickMath} from "fullrange/libraries/TickMath.sol";

import {ReservoirOracleUnderwriter, ReservoirOracle} from "src/ReservoirOracleUnderwriter.sol";
import {IPaprController} from "src/interfaces/IPaprController.sol";
import {PaprController} from "src/PaprController.sol";
import {Base} from "script/actions/Base.s.sol";

abstract contract MintableERC721 is ERC721 {
    function mint(address to) external virtual;
}

contract MintNFTAndBorrowMax is Base {
    MintableERC721 nft = MintableERC721(0x8232c5Fd480C2a74d2f25d3362f262fF3511CE49);
    // check next Id here https://goerli.etherscan.io/token/0x8232c5Fd480C2a74d2f25d3362f262fF3511CE49
    uint256 tokenId = 41;
    uint256 oraclePrice = 3e20;

    function run() public {
        // expected to mint tokenId
        vm.startBroadcast();
        nft.mint(deployer);
        vm.stopBroadcast();

        _openMaxLoanAndSwap(deployer);
    }

    function _openMaxLoanAndSwap(address borrower) internal {
        // IPaprController.OnERC721ReceivedArgs memory safeTransferReceivedArgs = IPaprController.OnERC721ReceivedArgs({
        //     increaseDebtOrProceedsTo: borrower,
        //     minOut: 0,
        //     debt: controller.maxDebt(oraclePrice) - 100,
        //     sqrtPriceLimitX96: _maxSqrtPriceLimit(true),
        //     oracleInfo: _getOracleInfoForCollateral(address(nft), oraclePrice)
        // });
        IPaprController.OnERC721ReceivedArgs memory safeTransferReceivedArgs = IPaprController.OnERC721ReceivedArgs({
            proceedsTo: borrower,
            debt: controller.maxDebt(oraclePrice) - 100,
            swapParams: IPaprController.SwapParams({
                amount: controller.maxDebt(oraclePrice) - 100,
                minOut: 1,
                sqrtPriceLimitX96: _maxSqrtPriceLimit(true),
                swapFeeTo: address(0),
                deadline: block.timestamp,
                swapFeeBips: 0
            }),
            oracleInfo: _getOracleInfoForCollateral(address(nft), oraclePrice)
        });
        nft.safeTransferFrom(borrower, address(controller), tokenId, abi.encode(safeTransferReceivedArgs));
    }

    function _maxSqrtPriceLimit(bool sellingPAPR) internal view returns (uint160) {
        bool token0IsUnderlying = controller.underlying() < controller.papr();
        if (sellingPAPR) {
            return !token0IsUnderlying ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1;
        } else {
            return token0IsUnderlying ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1;
        }
    }
}
