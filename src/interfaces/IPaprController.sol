// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import {ReservoirOracleUnderwriter} from "src/core/ReservoirOracleUnderwriter.sol";
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

    struct OnERC721ReceivedArgs {
        address mintDebtOrProceedsTo;
        uint256 minOut;
        uint256 debt;
        uint160 sqrtPriceLimitX96;
        ReservoirOracleUnderwriter.OracleInfo oracleInfo;
    }

    struct StrategyDefinition {
        uint256 targetAPR;
        uint256 maxLTV;
        ERC20 underlying;
    }

    struct CollateralAllowedConfig {
        address collateral;
        bool allowed;
    }

    /// @param minOut The minimum out amount the user wanted
    /// @param actualOut The actual out amount the user received
    error TooLittleOut(uint256 minOut, uint256 actualOut);

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
