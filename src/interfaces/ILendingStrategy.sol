// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import {ERC721} from "solmate/tokens/ERC721.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

interface ILendingStrategy {
    struct Collateral {
        ERC721 addr;
        uint256 id;
    }

    struct VaultInfo {
        uint128 debt;
        uint128 collateralValue;
    }

    enum OracleInfoPeriod {
        SevenDays,
        ThirtyDays,
        NinetyDays
    }

    struct OracleInfo {
        uint128 price;
        OracleInfoPeriod period;
    }

    struct Sig {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    struct OnERC721ReceivedArgs {
        uint256 vaultNonce;
        address mintVaultTo;
        address mintDebtOrProceedsTo;
        uint256 minOut;
        uint256 debt;
        uint160 sqrtPriceLimitX96;
        ILendingStrategy.OracleInfo oracleInfo;
        ILendingStrategy.Sig sig;
    }

    struct StrategyDefinition {
        uint256 targetAPR;
        uint256 maxLTV;
        ERC20 underlying;
    }

    struct SetAllowedCollateralArg {
        address addr;
        bool allowed;
    }

    /// @param minOut The minimum out amount the user wanted
    /// @param actualOut The actual out amount the user received
    error TooLittleOut(uint256 minOut, uint256 actualOut);

    error InvalidCollateralVaultIDCombination();

    /// @param vaultDebt how much debt the vault has
    /// @param maxDebt the max debt the vault is allowed to have
    error ExceedsMaxDebt(uint256 vaultDebt, uint256 maxDebt);

    error InvalidCollateral();
}
