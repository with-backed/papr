// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import {IPaprController} from "./IPaprController.sol";

interface IPostCollateralCallback {
    /// TODO: how will callers verify this is the right strategy?
    /// ours are not deterministic like uniswap, on just a few parameters.
    function postCollateralCallback(IPaprController.Collateral calldata collateral, bytes calldata data) external;
}
