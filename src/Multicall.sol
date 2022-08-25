// from https://github.com/Uniswap/v3-periphery/blob/22bce38f7aca940212964bdfdf319b94ead9c3a8/contracts/base/Multicall.sol
// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.13;

/// @title Multicall
/// @notice Enables calling multiple methods in a single call to the contract
abstract contract Multicall {
    function multicall(bytes[] calldata data)
        public
        returns (bytes[] memory results)
    {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            (bool success, bytes memory result) =
                address(this).delegatecall(data[i]);

            if (!success) {
                // Next 5 lines from https://ethereum.stackexchange.com/a/83577
                if (result.length < 68) {
                    revert();
                }
                assembly {
                    result := add(result, 0x04)
                }
                revert(abi.decode(result, (string)));
            }

            results[i] = result;
        }
    }
}
