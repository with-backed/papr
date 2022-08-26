// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IPostCollateralCallback} from
    "src/interfaces/IPostCollateralCallback.sol";
import {LendingStrategy} from "src/core/LendingStrategy.sol";
import {ILendingStrategy} from "src/interfaces/ILendingStrategy.sol";

contract Periphery is IPostCollateralCallback {
    
    function postCollateralCallback(
        ILendingStrategy.StrategyDefinition calldata strategyDefinition,
        ILendingStrategy.Collateral calldata collateral,
        bytes calldata data
    )
        external
    {
        // TODO use strategyDefinition to check that this is a legit strategy
        // see uniswap periphery PoolAddress
        address caller = abi.decode(data, (address));
        collateral.addr.transferFrom(caller, msg.sender, collateral.id);
    }
}
