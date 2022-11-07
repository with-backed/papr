// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC721, ERC721TokenReceiver} from "solmate/tokens/ERC721.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {SafeCast} from "v3-core/contracts/libraries/SafeCast.sol";
import {TickMath} from "fullrange/libraries/TickMath.sol";
import {INFTEDA, NFTEDAStarterIncentive} from "NFTEDA/extensions/NFTEDAStarterIncentive.sol";

import {DebtToken} from "./DebtToken.sol";
import {LinearPerpetual} from "./LinearPerpetual.sol";
import {Multicall} from "src/core/base/Multicall.sol";
import {ReservoirOracleUnderwriter} from "src/core/ReservoirOracleUnderwriter.sol";
import {IPostCollateralCallback} from "src/interfaces/IPostCollateralCallback.sol";
import {ILendingStrategy} from "src/interfaces/IPostCollateralCallback.sol";
import {OracleLibrary} from "src/libraries/OracleLibrary.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {BoringOwnable} from "@boringsolidity/BoringOwnable.sol";

contract LendingStrategy is
    LinearPerpetual,
    ERC721TokenReceiver,
    Multicall,
    BoringOwnable,
    ReservoirOracleUnderwriter,
    NFTEDAStarterIncentive
{
    using SafeCast for uint256;

    bool public immutable token0IsUnderlying;
    uint256 public liquidationAuctionMinSpacing = 2 days;
    uint256 public perPeriodAuctionDecayWAD = 0.7e18;
    uint256 public auctionDecayPeriod = 1 days;
    uint256 public auctionStartPriceMultiplier = 3;
    uint256 public liquidationPenaltyBips = 1000;

    // account => asset => vaultInfo
    mapping(address => mapping(ERC721 => ILendingStrategy.VaultInfo)) private _vaultInfo;
    // nft address => tokenId => account
    mapping(ERC721 => mapping(uint256 => address)) public collateralOwner;
    mapping(address => bool) public isAllowed;

    event IncreaseDebt(address indexed account, uint256 amount);
    event AddCollateral(address indexed account, ILendingStrategy.Collateral collateral);
    event ReduceDebt(address indexed account, uint256 amount);
    event RemoveCollateral(address indexed account, ILendingStrategy.Collateral collateral);

    event ChangeCollateralAllowed(ILendingStrategy.SetAllowedCollateralArg arg);

    constructor(
        string memory name,
        string memory symbol,
        uint256 maxLTV,
        uint256 indexMarkRatioMax,
        uint256 indexMarkRatioMin,
        ERC20 underlying,
        address oracleSigner
    )
        NFTEDAStarterIncentive(1e18)
        LinearPerpetual(
            underlying,
            new DebtToken(name, symbol, underlying.symbol()),
            maxLTV,
            indexMarkRatioMax,
            indexMarkRatioMin
        )
        ReservoirOracleUnderwriter(oracleSigner, address(underlying))
    {
        IUniswapV3Factory factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

        pool = IUniswapV3Pool(factory.createPool(address(underlying), address(perpetual), 10000));
        // TODO: get correct sqrtRatio for USDC vs. 18 decimals
        pool.initialize(TickMath.getSqrtRatioAtTick(0));
        token0IsUnderlying = pool.token0() == address(underlying);

        transferOwnership(msg.sender, false, false);

        _init();
    }

    function onERC721Received(address from, address, uint256 _id, bytes calldata data)
        external
        override
        returns (bytes4)
    {
        ILendingStrategy.OnERC721ReceivedArgs memory request = abi.decode(data, (ILendingStrategy.OnERC721ReceivedArgs));

        ILendingStrategy.Collateral memory collateral = ILendingStrategy.Collateral(ERC721(msg.sender), _id);

        _addCollateralToVault(from, collateral);

        if (request.minOut > 0) {
            _swap(
                request.mintDebtOrProceedsTo,
                !token0IsUnderlying,
                request.debt,
                request.minOut,
                request.sqrtPriceLimitX96,
                abi.encode(from, collateral.addr, address(this), request.oracleInfo)
            );
        } else if (request.debt > 0) {
            _increaseDebt(
                from, collateral.addr, request.mintDebtOrProceedsTo, uint256(request.debt), request.oracleInfo
            );
        }

        return ERC721TokenReceiver.onERC721Received.selector;
    }

    /// TODO consider passing token0IsUnderlying to save an SLOAD
    function mintAndSellDebt(
        ERC721 collateralAsset,
        uint256 debt,
        uint256 minOut,
        uint160 sqrtPriceLimitX96,
        address proceedsTo,
        ReservoirOracleUnderwriter.OracleInfo calldata oracleInfo
    ) public returns (uint256) {
        return _swap(
            proceedsTo,
            !token0IsUnderlying,
            debt,
            minOut,
            sqrtPriceLimitX96,
            abi.encode(msg.sender, collateralAsset, address(this), oracleInfo)
        );
    }

    function buyAndReduceDebt(
        address account,
        ERC721 collateralAsset,
        uint256 underlyingAmount,
        uint256 minOut,
        uint160 sqrtPriceLimitX96,
        address proceedsTo,
        ReservoirOracleUnderwriter.OracleInfo calldata oracleInfo
    ) public returns (uint256 out) {
        out = _swap(
            proceedsTo,
            token0IsUnderlying,
            underlyingAmount,
            minOut,
            sqrtPriceLimitX96,
            abi.encode(account, collateralAsset, msg.sender, oracleInfo)
        );
        reduceDebt(account, collateralAsset, uint96(out));
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata _data) external {
        require(amount0Delta > 0 || amount1Delta > 0); // swaps entirely within 0-liquidity regions are not supported

        if (msg.sender != address(pool)) {
            revert("wrong caller");
        }

        (address account, ERC721 asset, address payer, ReservoirOracleUnderwriter.OracleInfo memory oracleInfo) =
            abi.decode(_data, (address, ERC721, address, ReservoirOracleUnderwriter.OracleInfo));

        //determine the amount that needs to be repaid as part of the flashswap
        uint256 amountToPay = amount0Delta > 0 ? uint256(amount0Delta) : uint256(amount1Delta);

        if (payer == address(this)) {
            _increaseDebt(account, asset, msg.sender, amountToPay, oracleInfo);
        } else {
            underlying.transferFrom(payer, msg.sender, amountToPay);
        }
    }

    function addCollateral(ILendingStrategy.Collateral calldata collateral) public {
        _addCollateralToVault(msg.sender, collateral);
        collateral.addr.transferFrom(msg.sender, address(this), collateral.id);
    }

    /// Alternative to using safeTransferFrom,
    /// allows for loan to buy flows
    /// @dev anyone could use this method to add collateral to anyone else's vault
    /// we think this is acceptable and it is useful so that a periphery contract
    /// can modify the tx.origin's vault
    function addCollateralWithCallback(ILendingStrategy.Collateral calldata collateral, bytes calldata data) public {
        if (collateral.addr.ownerOf(collateral.id) == address(this)) {
            revert();
        }
        _addCollateralToVault(msg.sender, collateral);
        IPostCollateralCallback(msg.sender).postCollateralCallback(collateral, data);
        if (collateral.addr.ownerOf(collateral.id) != address(this)) {
            revert();
        }
    }

    function removeCollateral(
        address sendTo,
        ILendingStrategy.Collateral calldata collateral,
        ReservoirOracleUnderwriter.OracleInfo calldata oracleInfo
    ) external {
        if (collateralOwner[collateral.addr][collateral.id] != msg.sender) {
            revert ILendingStrategy.OnlyCollateralOwner();
        }

        delete collateralOwner[collateral.addr][collateral.id];

        uint16 newCount;
        unchecked {
            newCount = _vaultInfo[msg.sender][collateral.addr].count - 1;
            _vaultInfo[msg.sender][collateral.addr].count = newCount;
        }

        // allows for onReceive hook to sell and repay debt before the
        // debt check below
        collateral.addr.safeTransferFrom(address(this), sendTo, collateral.id);

        uint256 debt = _vaultInfo[msg.sender][collateral.addr].debt;
        uint256 oraclePrice =
            underwritePriceForCollateral(collateral.addr, ReservoirOracleUnderwriter.PriceKind.LOWER, oracleInfo);
        uint256 max = maxDebt(oraclePrice * newCount);

        if (debt > max) {
            revert ILendingStrategy.ExceedsMaxDebt(debt, max);
        }

        emit RemoveCollateral(msg.sender, collateral);
    }

    function increaseDebt(
        address mintTo,
        ERC721 asset,
        uint256 amount,
        ReservoirOracleUnderwriter.OracleInfo calldata oracleInfo
    ) public {
        _increaseDebt({account: msg.sender, asset: asset, mintTo: mintTo, amount: amount, oracleInfo: oracleInfo});
    }

    function reduceDebt(address account, ERC721 asset, uint256 amount) public {
        _reduceDebt({account: account, asset: asset, burnFrom: msg.sender, amount: amount});
    }

    function purchaseLiquidationAuctionNFT(
        Auction calldata auction,
        uint256 maxPrice,
        address sendTo,
        ReservoirOracleUnderwriter.OracleInfo calldata oracleInfo
    ) public {
        uint256 collateralValueCached = underwritePriceForCollateral(
            auction.auctionAssetContract, ReservoirOracleUnderwriter.PriceKind.TWAP, oracleInfo
        ) * _vaultInfo[auction.nftOwner][auction.auctionAssetContract].count;
        bool isLastCollateral = collateralValueCached == 0;

        uint256 debtCached = _vaultInfo[auction.nftOwner][auction.auctionAssetContract].debt;
        uint256 maxDebtCached = isLastCollateral ? debtCached : maxDebt(collateralValueCached);
        /// anything above what is needed to bring this vault under maxDebt is considered excess
        uint256 neededToSaveVault = maxDebtCached > debtCached ? 0 : debtCached - maxDebtCached;
        uint256 price = _purchaseNFT(auction, maxPrice, sendTo);
        uint256 excess = price > neededToSaveVault ? price - neededToSaveVault : 0;
        uint256 remaining;

        if (excess > 0) {
            remaining = _handleExcess(excess, neededToSaveVault, debtCached, auction);
        } else {
            _reduceDebt(auction.nftOwner, auction.auctionAssetContract, address(this), price);
            remaining = debtCached - price;
        }

        if (isLastCollateral && remaining != 0) {
            /// there will be debt left with no NFTs, set it to 0
            _reduceDebtWithoutBurn(auction.nftOwner, auction.auctionAssetContract, remaining);
        }
    }

    function _handleExcess(uint256 excess, uint256 neededToSaveVault, uint256 debtCached, Auction calldata auction)
        internal
        returns (uint256 remaining)
    {
        uint256 fee = excess * liquidationPenaltyBips / 1e4;
        uint256 credit = excess - fee;
        uint256 totalOwed = credit + neededToSaveVault;

        DebtToken(address(perpetual)).burn(address(this), fee);

        if (totalOwed > debtCached) {
            // we owe them more papr than they have in debt
            // so we pay down debt and send them the rest
            _reduceDebt(auction.nftOwner, auction.auctionAssetContract, address(this), debtCached);
            perpetual.transfer(auction.nftOwner, totalOwed - debtCached);
        } else {
            // reduce vault debt
            _reduceDebt(auction.nftOwner, auction.auctionAssetContract, address(this), totalOwed);
            remaining = debtCached - totalOwed;
        }
    }

    function startLiquidationAuction(
        address account,
        ILendingStrategy.Collateral calldata collateral,
        ReservoirOracleUnderwriter.OracleInfo calldata oracleInfo
    ) public returns (INFTEDA.Auction memory auction) {
        uint256 norm = updateNormalization();

        ILendingStrategy.VaultInfo storage info = _vaultInfo[account][collateral.addr];

        // check collateral belongs to account
        if (collateralOwner[collateral.addr][collateral.id] != account) {
            revert ILendingStrategy.InvalidCollateralAccountPair();
        }

        uint256 oraclePrice =
            underwritePriceForCollateral(collateral.addr, ReservoirOracleUnderwriter.PriceKind.TWAP, oracleInfo);
        if (info.debt < maxDebt(oraclePrice * info.count)) {
            revert ILendingStrategy.NotLiquidatable();
        }

        if (block.timestamp - info.latestAuctionStartTime < liquidationAuctionMinSpacing) {
            revert ILendingStrategy.MinAuctionSpacing();
        }

        info.latestAuctionStartTime = uint40(block.timestamp);
        info.count -= 1;

        delete collateralOwner[collateral.addr][collateral.id];

        _startAuction(
            auction = Auction({
                nftOwner: account,
                auctionAssetID: collateral.id,
                auctionAssetContract: collateral.addr,
                perPeriodDecayPercentWad: perPeriodAuctionDecayWAD,
                secondsInPeriod: auctionDecayPeriod,
                // start price is frozen price * auctionStartPriceMultiplier,
                // converted to perpetual value at the current contract price
                startPrice: (oraclePrice * auctionStartPriceMultiplier) * FixedPointMathLib.WAD / norm,
                paymentAsset: perpetual
            })
        );
    }

    // normalization value at liquidation
    // i.e. the debt token:underlying internal contract exchange rate (normalization)
    // at which this vault will be liquidated
    function liquidationPrice(address account, ERC721 asset, uint256 collateralPrice) public view returns (uint256) {
        uint256 debt = _vaultInfo[account][asset].debt;
        if (debt == 0) {
            revert ILendingStrategy.AccountHasNoDebt();
        } else {
            // TODO do we need to divide out WAD?
            uint256 maxLoanUnderlying = _vaultInfo[account][asset].count * collateralPrice * maxLTV;
            return maxLoanUnderlying / debt;
        }
    }

    function maxDebt(uint256 totalCollateraValue) public view returns (uint256) {
        uint256 maxLoanUnderlying = totalCollateraValue * maxLTV;
        return maxLoanUnderlying / normalization;
    }

    function vaultTotalCollateralValue(address account, ERC721 asset, uint256 price) public view returns (uint256) {
        return _vaultInfo[account][asset].count * price;
    }

    // function collateralHash(ILendingStrategy.Collateral memory collateral, address account)
    //     public
    //     pure
    //     returns (bytes32)
    // {
    //     return keccak256(abi.encode(collateral, account));
    // }

    function vaultInfo(address account, ERC721 asset) public view returns (ILendingStrategy.VaultInfo memory) {
        return _vaultInfo[account][asset];
    }

    function setAllowedCollateral(ILendingStrategy.SetAllowedCollateralArg[] calldata args) public onlyOwner {
        for (uint256 i = 0; i < args.length;) {
            isAllowed[args[i].addr] = args[i].allowed;
            emit ChangeCollateralAllowed(args[i]);
            unchecked {
                ++i;
            }
        }
    }

    function _swap(
        address recipient,
        bool zeroForOne,
        uint256 amountSpecified,
        uint256 minOut,
        uint160 sqrtPriceLimitX96,
        bytes memory data
    ) internal returns (uint256 out) {
        (int256 amount0, int256 amount1) = pool.swap(
            recipient,
            zeroForOne,
            amountSpecified.toInt256(),
            sqrtPriceLimitX96 == 0
                ? (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
                : sqrtPriceLimitX96,
            data
        );

        out = uint256(-(zeroForOne ? amount1 : amount0));

        if (out < minOut) {
            revert ILendingStrategy.TooLittleOut(out, minOut);
        }
    }

    function _increaseDebt(
        address account,
        ERC721 asset,
        address mintTo,
        uint256 amount,
        ReservoirOracleUnderwriter.OracleInfo memory oracleInfo
    ) internal {
        updateNormalization();

        uint256 newDebt = _vaultInfo[account][asset].debt + amount;
        uint256 oraclePrice =
            underwritePriceForCollateral(asset, ReservoirOracleUnderwriter.PriceKind.LOWER, oracleInfo);

        // TODO do we need to check if oraclePrice is 0?

        uint256 max = maxDebt(_vaultInfo[account][asset].count * oraclePrice);
        if (newDebt > max) {
            revert ILendingStrategy.ExceedsMaxDebt(newDebt, max);
        }

        // TODO safeCast
        _vaultInfo[account][asset].debt = uint200(newDebt);
        DebtToken(address(perpetual)).mint(mintTo, amount);

        emit IncreaseDebt(account, amount);
    }

    function _addCollateralToVault(address account, ILendingStrategy.Collateral memory collateral) internal {
        if (!isAllowed[address(collateral.addr)]) {
            revert ILendingStrategy.InvalidCollateral();
        }

        collateralOwner[collateral.addr][collateral.id] = account;
        _vaultInfo[account][collateral.addr].count += 1;

        emit AddCollateral(account, collateral);
    }

    function _reduceDebt(address account, ERC721 asset, address burnFrom, uint256 amount) internal {
        _reduceDebtWithoutBurn(account, asset, amount);
        DebtToken(address(perpetual)).burn(burnFrom, amount);
    }

    function _reduceDebtWithoutBurn(address account, ERC721 asset, uint256 amount) internal {
        _vaultInfo[account][asset].debt = uint200(_vaultInfo[account][asset].debt - amount);
        emit ReduceDebt(account, amount);
    }
}
