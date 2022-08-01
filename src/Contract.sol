// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

struct Collateral {
    address addr;
    uint256 amountOrId;
}

struct Loan {
    Collateral collateral;
    // the oracle price is frozen when loan is created
    // there is no oracle based liquidations
    uint256 oraclePrice;
}

// what if we could give people loans of custom duration with the same insturment? 
// daily APR is the same no matter what? So if you want a three day loan, you can borrow X much? 
// the question is just how much the borrowed relative to how much we have a tolerance for?
// but how is the tolerance set? It is on origination on a per loan basis? So you
// don't receive any benefit if the price goes up, but you're not hurt if it goes down
// so we could just save the price, and know that we only ever lend at 50% of the price? 
// so if you want a longer loan you get less? 

enum OracleInfoPeriod { 7DAYS; 30DAYS; 90DAYS }

struct OracleInfo {
    uint256 price;
    OracleInfoPeriod period;
}

struct Sig {
    uint8 v;
    bytes32 r;
    bytes32 s;
}

contract Contract {
    uint256 constant ONE = 1e18;
    uint256 constant maxLTV = ONE * 5 / 100;
    uint256 normalization = ONE;
    mapping(bytes32 => uint256) public debt;

    function borrow(Loan calldata loan, OracleInfo calldata oracleInfo, Sig calldata sig) external {

    }

    function payDebt()
}
