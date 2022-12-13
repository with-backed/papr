// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "src/NFTEDA/extensions/SimpleNFTEDA.sol";
import {NFTEDATest} from "test/NFTEDA/NFTEDA.t.sol";
import {TestSimpleNFTEDA} from "test/NFTEDA/mocks/TestSimpleNFTEDA.sol";

contract SimpleNFTEDATest is NFTEDATest {
    function _createAuctionContract() internal override {
        auctionContract = new TestSimpleNFTEDA();
    }
}
