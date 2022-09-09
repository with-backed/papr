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
        uint256 vaultId;
        uint256 vaultNonce;
        address mintVaultTo;
        address mintDebtOrProceedsTo;
        uint256 minOut;
        int256 debt;
        uint160 sqrtPriceLimitX96;
        ILendingStrategy.OracleInfo oracleInfo;
        ILendingStrategy.Sig sig;
    }

    struct StrategyDefinition {
        bytes32 allowedCollateralRoot;
        uint256 targetAPR;
        uint256 maxLTV;
        ERC20 underlying;
    }
}
