// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

contract MinimalObservablePool {
    int56[] tickCumulatives;

    function setTickComulatives(int56[] calldata _tickCumulatives) external {
        tickCumulatives = _tickCumulatives;
    }


    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory, uint160[] memory)
    {
        int56[] memory _tickCumulatives = new int56[](secondsAgos.length);
        uint160[] memory _secondsPerLiquidityCumulativeX128s = new uint160[](secondsAgos.length);
        for (uint i = 0; i < secondsAgos.length; i++) {
            _tickCumulatives[i] = tickCumulatives[i];
            _secondsPerLiquidityCumulativeX128s[i] = 0;
        }

        return (_tickCumulatives, _secondsPerLiquidityCumulativeX128s);
    }
}
