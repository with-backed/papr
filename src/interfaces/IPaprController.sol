// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import {ReservoirOracleUnderwriter} from "src/ReservoirOracleUnderwriter.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {INFTEDA} from "NFTEDA/extensions/NFTEDAStarterIncentive.sol";

interface IPaprController {
    /// @notice emitted when a user adds debt to their vault
    /// @param account address increasing their debt
    /// @param collateralAddress address of the collateral token
    /// @param amount amount of debt added
    event IncreaseDebt(address indexed account, ERC721 indexed collateralAddress, uint256 amount);
    /// @notice emitted when a user adds collateral to their vault
    /// @param account address adding collateral
    /// @param collateral collateral added
    event AddCollateral(address indexed account, IPaprController.Collateral collateral);
    /// @notice emitted when a user removes debt from their vault
    /// @param account address reducing their debt
    /// @param collateralAddress address of the collateral token
    /// @param amount amount of debt removed
    event ReduceDebt(address indexed account, ERC721 indexed collateralAddress, uint256 amount);
    /// @notice emitted when a user removes collateral from their vault
    /// @param account address removing collateral
    /// @param collateral collateral removed
    event RemoveCollateral(address indexed account, IPaprController.Collateral collateral);
    /// @notice emitted when a controller toggles collateral allowance
    /// @param collateral address of the collateral token
    /// @param isAllowed whether the collateral is allowed
    event AllowCollateral(address indexed collateral, bool isAllowed);

    /// @param vaultDebt how much debt the vault has
    /// @param maxDebt the max debt the vault is allowed to have
    error ExceedsMaxDebt(uint256 vaultDebt, uint256 maxDebt);
    error InvalidCollateral();
    error MinAuctionSpacing();
    error NotLiquidatable();
    error InvalidCollateralAccountPair();
    error AccountHasNoDebt();
    error OnlyCollateralOwner();

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

    /// @notice adds collateral to a vault
    /// @param collateral collateral to add
    function addCollateral(IPaprController.Collateral calldata collateral) external;

    /// @notice removes collateral from a vault
    /// @param sendTo address to send the collateral to when removed
    /// @param collateral collateral to remove
    /// @param oracleInfo TWAP oracle information for the collateral being removed
    function removeCollateral(
        address sendTo,
        IPaprController.Collateral calldata collateral,
        ReservoirOracleUnderwriter.OracleInfo calldata oracleInfo
    ) external;

    /// @notice adds debt to a vault
    /// @param mintTo address to mint the debt to
    /// @param asset address of the collateral token used to mint the debt
    /// @param amount amount of debt to mint
    /// @param oracleInfo LOWER oracle information for the collateral being used to mint debt
    function increaseDebt(
        address mintTo,
        ERC721 asset,
        uint256 amount,
        ReservoirOracleUnderwriter.OracleInfo calldata oracleInfo
    ) external;

    /// @notice removes debt from a vault
    /// @param account address reducing their debt
    /// @param asset address of the collateral token the user would like to remove debt from
    /// @param amount amount of debt to remove
    function reduceDebt(address account, ERC721 asset, uint256 amount) external;

    /// @notice adds debt to a vault and swaps the debt for the controller's underlying token on Uniswap
    /// @param proceedsTo address to send the proceeds to
    /// @param collateralAsset address of the collateral token used to mint the debt
    /// @param params parameters for the swap
    /// @param oracleInfo LOWER oracle information for the collateral being used to mint debt
    /// @return amount amount of underlying token received by the user
    function increaseDebtAndSell(
        address proceedsTo,
        ERC721 collateralAsset,
        IPaprController.SwapParams calldata params,
        ReservoirOracleUnderwriter.OracleInfo calldata oracleInfo
    ) external returns (uint256);

    /// @notice removes debt from a vault by buying it on Uniswap in exchange for the controller's underlying token
    /// @param account address reducing their debt
    /// @param collateralAsset address of the collateral token the user would like to remove debt from
    /// @param params parameters for the swap
    /// @return amount amount of debt received from the swap and paid down by the user
    function buyAndReduceDebt(address account, ERC721 collateralAsset, IPaprController.SwapParams calldata params)
        external
        returns (uint256);

    /// @notice purchases a liquidation auction with the controller's papr token
    /// @param auction auction to purchase
    /// @param maxPrice maximum price to pay for the auction
    /// @param sendTo address to send the collateral to if auction is won
    function purchaseLiquidationAuctionNFT(
        INFTEDA.Auction calldata auction,
        uint256 maxPrice,
        address sendTo,
        ReservoirOracleUnderwriter.OracleInfo calldata oracleInfo
    ) external;

    /// @notice starts a liquidation auction for a vault if it is liquidatable
    /// @param account address of the user who's vault to liquidate
    /// @param collateral collateral to liquidate
    /// @param oracleInfo TWAP oracle information for the collateral being liquidated
    /// @return auction auction that was started
    function startLiquidationAuction(
        address account,
        IPaprController.Collateral calldata collateral,
        ReservoirOracleUnderwriter.OracleInfo calldata oracleInfo
    ) external returns (INFTEDA.Auction memory auction);

    /// @notice sets the Uniswap V3 pool that is used to determine mark
    /// @param _pool address of the Uniswap V3 pool
    function setPool(address _pool) external;

    /// @notice sets the funding period for interest payments
    /// @param _fundingPeriod new funding period in seconds
    function setFundingPeriod(uint256 _fundingPeriod) external;

    /// @notice sets whether a collateral is allowed to be used to mint debt
    /// @param collateralConfigs configurations setting whether a collateral is allowed or not
    function setAllowedCollateral(IPaprController.CollateralAllowedConfig[] calldata collateralConfigs) external;

    /// @notice returns the maximum debt that can be minted for a given collateral value
    /// @param totalCollateraValue total value of the collateral
    /// @return maxDebt maximum debt that can be minted, expressed in papr token terms
    function maxDebt(uint256 totalCollateraValue) external view returns (uint256);

    /// @notice returns information about a vault
    /// @param account address of the vault owner
    /// @param asset address of the collateral token associated with the vault
    /// @return vaultInfo VaultInfo struct representing information about a vault
    function vaultInfo(address account, ERC721 asset) external view returns (IPaprController.VaultInfo memory);
}
