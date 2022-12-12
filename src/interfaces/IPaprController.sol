// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import {ReservoirOracleUnderwriter} from "src/ReservoirOracleUnderwriter.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

interface IPaprController {
    struct Collateral {
        ERC721 addr;
        uint256 id;
    }

    struct VaultInfo {
        uint16 count;
        uint40 latestAuctionStartTime;
        uint200 debt;
    }

    struct SwapParams {
        uint256 amount;
        uint256 minOut;
        uint160 sqrtPriceLimitX96;
        address swapFeeTo;
        uint256 swapFeeBips;
    }

    struct OnERC721ReceivedArgs {
        address proceedsTo;
        /// @dev debt is ignore in favor of `swapParams.amount` of minOut > 0
        uint256 debt;
        SwapParams swapParams;
        ReservoirOracleUnderwriter.OracleInfo oracleInfo;
    }

    struct CollateralAllowedConfig {
        address collateral;
        bool allowed;
    }

    /// @param vaultDebt how much debt the vault has
    /// @param maxDebt the max debt the vault is allowed to have
    error ExceedsMaxDebt(uint256 vaultDebt, uint256 maxDebt);

    error InvalidCollateral();

    error MinAuctionSpacing();

    error NotLiquidatable();

    error InvalidCollateralAccountPair();

    error AccountHasNoDebt();

    error OnlyCollateralOwner();
}
