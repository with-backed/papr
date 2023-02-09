// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.17;

import {ERC20} from "solmate/tokens/ERC20.sol";
import "forge-std/Test.sol";

import {MockFundingRateController} from "test/mocks/MockFundingRateController.sol";
import {MinimalObservablePool} from "test/mocks/uniswap/MinimalObservablePool.sol";
import {TestERC20} from "test/mocks/TestERC20.sol";
import {
    IUniswapOracleFundingRateController,
    IFundingRateController
} from "src/interfaces/IUniswapOracleFundingRateController.sol";
import {OracleLibrary} from "src/libraries/OracleLibrary.sol";

contract TestERC20Papr is ERC20("papr", "papr,", 18) {
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract BaseUniswapOracleFundingRateControllerTest is Test {
    event UpdateTarget(uint256 newTarget);
    event SetPool(address indexed pool);
    event SetFundingPeriod(uint256 fundingPeriod);

    MockFundingRateController fundingRateController;

    ERC20 underlying = new TestERC20();
    ERC20 papr = new TestERC20Papr();
    uint256 indexMarkRatioMax = 3e18;
    uint256 indexMarkRatioMin = 0.5e18;

    function setUp() public {
        fundingRateController = new MockFundingRateController(underlying, papr);
        fundingRateController.init(1e6, 0);
        fundingRateController.setPoolCheat(address(new MinimalObservablePool(underlying, papr)));
        int56[] memory _tickCumulatives = new int56[](1);
        _tickCumulatives[0] = 200;
        MinimalObservablePool(fundingRateController.pool()).setTickComulatives(_tickCumulatives);
    }
}
