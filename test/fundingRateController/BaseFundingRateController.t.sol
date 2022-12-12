// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import "forge-std/Test.sol";

import {MockFundingRateController} from "test/mocks/MockFundingRateController.sol";
import {MinimalObservablePool} from "test/mocks/uniswap/MinimalObservablePool.sol";
import {TestERC20} from "test/mocks/TestERC20.sol";
import {TickMath} from "fullrange/libraries/TickMath.sol";
import {
    IUniswapOracleFundingRateController,
    IFundingRateController
} from "src/interfaces/IUniswapOracleFundingRateController.sol";

contract BaseFundingRateControllerTest is Test {
    event UpdateTarget(uint256 newTarget);
    event SetPool(address indexed pool);
    event SetFundingPeriod(uint256 fundingPeriod);

    MockFundingRateController fundingRateController;

    ERC20 underlying = new TestERC20();
    ERC20 papr = new TestERC20();
    uint256 indexMarkRatioMax = 1.2e18;
    uint256 indexMarkRatioMin = 0.8e18;

    function setUp() public {
        fundingRateController = new MockFundingRateController(underlying, papr, indexMarkRatioMax, indexMarkRatioMin);
        fundingRateController.init(1e18, 0);
        fundingRateController.setPool(address(new MinimalObservablePool(underlying, papr)));
        int56[] memory _tickCumulatives = new int56[](1);
        _tickCumulatives[0] = 0;
        MinimalObservablePool(fundingRateController.pool()).setTickComulatives(_tickCumulatives);
    }
}
