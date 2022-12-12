// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IFundingRateController {
    event SetPool(address indexed pool);

    error PoolTokensDoNotMatch();
}