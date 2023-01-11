// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import {BasePaprControllerTest} from "./BasePaprController.ft.sol";

contract InvariantTest {

    address[] private _targetContracts;

    function addTargetContract(address newTargetContract_) internal {
        _targetContracts.push(newTargetContract_);
    }

    function targetContracts() public view returns (address[] memory targetContracts_) {
        require(_targetContracts.length != uint256(0), "NO_TARGET_CONTRACTS");
        return _targetContracts;
    }

}


contract PaprControllerInvariantTest is BasePaprControllerTest, InvariantTest {
    function setUp() public override {
        super.setUp();
        addTargetContract(address(controller));
        addTargetContract(address(controller.papr()));
        addTargetContract(address(controller.underlying()));
        addTargetContract(address(nft));
    }

    function invariant_one() public {
        assertEq(controller.papr().totalSupply(), 0, 'violated');
    }

}

