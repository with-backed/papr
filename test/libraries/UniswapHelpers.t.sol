// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import {IUniswapV3PoolActions} from "v3-core/contracts/interfaces/pool/IUniswapV3PoolActions.sol";
import "forge-std/Test.sol";

import {UniswapHelpers} from "../../src/libraries/UniswapHelpers.sol";

contract UniswapHelpersTest is Test {
    address pool = address(12345);

    function setUp() public {}

    function testSwapRevertsIfDeadlinePassed() public {
        vm.expectRevert(
            abi.encodeWithSelector(UniswapHelpers.PassedDeadline.selector, block.timestamp - 1, block.timestamp)
        );
        UniswapHelpers.swap(pool, address(1), false, 1e18, 0, 10, block.timestamp - 1, "");
    }

    /// @dev not working due to an issue of using mockCall and expectRevert together.
    /// Need to switch to a fork test if we want to work like this
    // function testSwapRevertsIfMintOutTooLittle() public {
    //     bytes memory mockCall =
    //         abi.encodeWithSelector(IUniswapV3PoolActions.swap.selector, address(1), true, 1e18, 1, "");
    //     uint256 out = 10;
    //     uint256 minOut = out + 1;
    //     bytes memory mockResponse = abi.encode(10, -int256(out));
    //     vm.mockCall(pool, mockCall, mockResponse);
    //     vm.expectRevert(
    //         abi.encodeWithSelector(UniswapHelpers.TooLittleOut.selector, 10, 11)
    //     );
    //     UniswapHelpers.swap(pool, address(1), true, 1e18, minOut, 1, block.timestamp, "");
    // }
}
