// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import {ReservoirOracleUnderwriter} from "src/ReservoirOracleUnderwriter.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {INFTEDA} from "src/NFTEDA/extensions/NFTEDAStarterIncentive.sol";

interface IPaprController {
    /// @notice collateral for a vault
    struct Collateral {
        /// @dev address of the collateral, cast to ERC721
        ERC721 addr;
        /// @dev tokenId of the collateral
        uint256 id;
    }

    /// @notice vault information for a vault
    struct VaultInfo {
        /// @dev number of collateral tokens in the vault
        uint16 count;
        /// @dev start time of last auction the vault underwent, 0 if no auction has been started
        uint40 latestAuctionStartTime;
        /// @dev debt of the vault, expressed in papr token units
        uint200 debt;
    }

    /// @notice parameters describing a swap
    /// @dev increaseDebtAndSell has the input token as papr and output token as the underlying
    /// @dev buyAndReduceDebt has the input token as the underlying and output token as papr
    struct SwapParams {
        /// @dev amount of input token to swap
        uint256 amount;
        /// @dev minimum amount of output token to be received
        uint256 minOut;
        /// @dev sqrt price limit for the swap
        uint160 sqrtPriceLimitX96;
        /// @dev optional address to receive swap fees
        address swapFeeTo;
        /// @dev optional swap fee in bips
        uint256 swapFeeBips;
    }

    /// @notice parameters to be encoded in safeTransferFrom collateral addition
    struct OnERC721ReceivedArgs {
        /// @dev address to send proceeds to if minting debt or swapping
        address proceedsTo;
        /// @dev debt is ignored in favor of `swapParams.amount` of minOut > 0
        uint256 debt;
        /// @dev optional swapParams
        SwapParams swapParams;
        /// @dev oracle information associated with collateral being sent
        ReservoirOracleUnderwriter.OracleInfo oracleInfo;
    }

    /// @notice parameters to change what collateral addresses can be used for a vault
    struct CollateralAllowedConfig {
        address collateral;
        bool allowed;
    }

    /// @notice returns who owns a collateral token in a vault
    /// @param collateral address of the collateral
    /// @param tokenId tokenId of the collateral
    function collateralOwner(ERC721 collateral, uint256 tokenId) external view returns (address);

    /// @notice returns whether a token address is allowed to serve as collateral for a vault
    /// @param collateral address of the collateral token
    function isAllowed(address collateral) external view returns (bool);

    /// @notice emitted when an address increases the debt balance of their vault
    /// @param account address increasing their debt
    /// @param collateralAddress address of the collateral token
    /// @param amount amount of debt added
    /// @dev vaults are uniquely identified by the address of the vault owner and the address of the collateral token used in the vault
    event IncreaseDebt(address indexed account, ERC721 indexed collateralAddress, uint256 amount);

    /// @notice emitted when a user adds collateral to their vault
    /// @param account address adding collateral
    /// @param collateral collateral added
    event AddCollateral(address indexed account, IPaprController.Collateral collateral);

    /// @notice emitted when a user reduces the debt balance of their vault
    /// @param account address reducing their debt
    /// @param collateralAddress address of the collateral token
    /// @param amount amount of debt removed
    event ReduceDebt(address indexed account, ERC721 indexed collateralAddress, uint256 amount);

    /// @notice emitted when a user removes collateral from their vault
    /// @param account address removing collateral
    /// @param collateral collateral removed
    event RemoveCollateral(address indexed account, IPaprController.Collateral collateral);

    /// @notice emitted when the owner sets whether a token address is allowed to serve as collateral for a vault
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

    error DebtAmountExceedsUint200();

    /// @notice boolean indicating whether token0 in pool is the underlying token
    function token0IsUnderlying() external view returns (bool);

    /// @notice maximum LTV a vault can have, expressed as a decimal scaled by 1e18
    function maxLTV() external view returns (uint256);

    /// @notice minimum time that must pass before consecutive collateral is liquidated from the same vault
    function liquidationAuctionMinSpacing() external view returns (uint256);

    /// @notice amount the price of an auction decreases by per auctionDecayPeriod, expressed as a decimal scaled by 1e18
    function perPeriodAuctionDecayWAD() external view returns (uint256);

    /// @notice amount of time that perPeriodAuctionDecayWAD is applied to, expressed in seconds
    function auctionDecayPeriod() external view returns (uint256);

    /// @notice the multiplier for the starting price of an auction, applied to the current price of the collateral in papr tokens
    function auctionStartPriceMultiplier() external view returns (uint256);

    /// @notice fee paid by the vault owner when their vault is liquidated if there was excess debt credited to their vault, in bips
    function liquidationPenaltyBips() external view returns (uint256);

    /// @notice adds collateral to msg.senders vault
    /// @param collateral collateral to add
    function addCollateral(IPaprController.Collateral calldata collateral) external;

    /// @notice removes collateral from msg.senders vault
    /// @param sendTo address to send the collateral to when removed
    /// @param collateral collateral to remove
    /// @param oracleInfo oracle information for the collateral being removed
    /// @dev removing collateral expects the TWAP price information from the oracle
    function removeCollateral(
        address sendTo,
        IPaprController.Collateral calldata collateral,
        ReservoirOracleUnderwriter.OracleInfo calldata oracleInfo
    ) external;

    /// @notice increases debt balance of the vault uniquely identified by msg.sender and the collateral address
    /// @param mintTo address to mint the debt to
    /// @param asset address of the collateral token used to mint the debt
    /// @param amount amount of debt to mint
    /// @param oracleInfo oracle information for the collateral being used to mint debt
    /// @dev increasing debt expects the LOWER price information from the oracle
    function increaseDebt(
        address mintTo,
        ERC721 asset,
        uint256 amount,
        ReservoirOracleUnderwriter.OracleInfo calldata oracleInfo
    ) external;

    /// @notice removes and burns debt from the vault uniquely identified by account and the collateral address
    /// @param account address reducing their debt
    /// @param asset address of the collateral token the user would like to remove debt from
    /// @param amount amount of debt to remove
    function reduceDebt(address account, ERC721 asset, uint256 amount) external;

    /// @notice mints debt and swaps the debt for the controller's underlying token on Uniswap
    /// @param proceedsTo address to send the proceeds to
    /// @param collateralAsset address of the collateral token used to mint the debt
    /// @param params parameters for the swap
    /// @param oracleInfo oracle information for the collateral being used to mint debt
    /// @dev increasing debt expects the LOWER price information from the oracle
    /// @return amount amount of underlying token received by the user
    function increaseDebtAndSell(
        address proceedsTo,
        ERC721 collateralAsset,
        IPaprController.SwapParams calldata params,
        ReservoirOracleUnderwriter.OracleInfo calldata oracleInfo
    ) external returns (uint256);

    /// @notice removes debt from a vault and burns it by buying it on Uniswap in exchange for the controller's underlying token
    /// @param account address reducing their debt
    /// @param collateralAsset address of the collateral token the user would like to remove debt from
    /// @param params parameters for the swap
    /// @return amount amount of debt received from the swap and burned
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
    /// @param oracleInfo oracle information for the collateral being liquidated
    /// @dev liquidating collateral expects the TWAP price information from the oracle
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
    /// @param collateralConfigs configuration settings indicating whether a collateral is allowed or not
    function setAllowedCollateral(IPaprController.CollateralAllowedConfig[] calldata collateralConfigs) external;

    /// @notice returns the maximum debt that can be minted for a given collateral value
    /// @param totalCollateraValue total value of the collateral
    /// @return maxDebt maximum debt that can be minted, expressed in terms of the papr token
    function maxDebt(uint256 totalCollateraValue) external view returns (uint256);

    /// @notice returns information about a vault
    /// @param account address of the vault owner
    /// @param asset address of the collateral token associated with the vault
    /// @return vaultInfo VaultInfo struct representing information about a vault
    function vaultInfo(address account, ERC721 asset) external view returns (IPaprController.VaultInfo memory);

    /// @notice transfers papr tokens held in controller from auction fees
    /// @param to address to send papr tokens to
    /// @param amount amount of papr to send
    /// @dev only controller owner will be able to execute this function
    function sendPaprFromAuctionFees(address to, uint256 amount) external;

    /// @notice burns papr tokens held in controller from auction fees
    /// @param amount amount of papr to burn
    /// @dev only controller owner will be able to execute this function
    function burnPaprFromAuctionFees(uint256 amount) external;
}
