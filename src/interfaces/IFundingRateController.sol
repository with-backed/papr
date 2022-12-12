// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IFundingRateController {
    event UpdateTarget(uint256 newTarget);
    event SetPool(address indexed pool);
    event SetFundingPeriod(uint256 fundingPeriod);

    error PoolTokensDoNotMatch();
    error AlreadyInitialized();
    error FundingPeriodTooShort();
    error FundingPeriodTooLong();

    function lastUpdated() external returns (uint256);
    function target() external returns (uint256);
}
