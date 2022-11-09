// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IPostCollateralCallback} from "src/interfaces/IPostCollateralCallback.sol";
import {PaprController} from "src/core/PaprController.sol";
import {IPaprController} from "src/interfaces/IPaprController.sol";

contract Periphery is IPostCollateralCallback {
    function postCollateralCallback(IPaprController.Collateral calldata collateral, bytes calldata data) external {
        address caller = abi.decode(data, (address));
        collateral.addr.transferFrom(caller, msg.sender, collateral.id);
    }
}
