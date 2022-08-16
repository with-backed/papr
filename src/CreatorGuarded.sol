// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract CreatorGuarded {
    address creator;

    error CreatorOnly();

    modifier onlyCreator() {
        if (msg.sender != creator) {
            revert CreatorOnly();
        }
        _;
    }

    constructor() {
        creator = msg.sender;
    }
}
