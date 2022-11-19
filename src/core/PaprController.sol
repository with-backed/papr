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

import {PaprToken} from "./PaprToken.sol";
import {FundingRateController} from "./FundingRateController.sol";
import {Multicall} from "src/core/base/Multicall.sol";
import {ReservoirOracleUnderwriter} from "src/core/ReservoirOracleUnderwriter.sol";
import {IPostCollateralCallback} from "src/interfaces/IPostCollateralCallback.sol";
import {IPaprController} from "src/interfaces/IPaprController.sol";
import {OracleLibrary} from "src/libraries/OracleLibrary.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {BoringOwnable} from "@boringsolidity/BoringOwnable.sol";

contract PaprController is
    FundingRateController,
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
    mapping(address => mapping(ERC721 => IPaprController.VaultInfo)) private _vaultInfo;
    // nft address => tokenId => account
    mapping(ERC721 => mapping(uint256 => address)) public collateralOwner;
    mapping(address => bool) public isAllowed;

    event IncreaseDebt(address indexed account, ERC721 indexed collateralAddress, uint256 amount);
    event AddCollateral(address indexed account, IPaprController.Collateral collateral);
    event ReduceDebt(address indexed account, ERC721 indexed collateralAddress, uint256 amount);
    event RemoveCollateral(address indexed account, IPaprController.Collateral collateral);

    event ChangeCollateralAllowed(IPaprController.SetAllowedCollateralArg arg);

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
        FundingRateController(
            underlying,
            new PaprToken(name, symbol, underlying.symbol()),
            maxLTV,
            indexMarkRatioMax,
            indexMarkRatioMin
        )
        ReservoirOracleUnderwriter(oracleSigner, address(underlying))
    {
        IUniswapV3Factory factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

        pool = IUniswapV3Pool(factory.createPool(address(underlying), address(perpetual), 10000));
        token0IsUnderlying = pool.token0() == address(underlying);
        uint256 underlyingONE = 10 ** underlying.decimals();

        // initialize the pool at 1:1
        pool.initialize(
            TickMath.getSqrtRatioAtTick(
                TickMath.getTickAtSqrtRatio(
                    uint160(
                        token0IsUnderlying ? (((10 ** 18) << 96) / underlyingONE) : ((underlyingONE << 96) / (10 ** 18))
                    )
                ) / 2
            )
        );

        transferOwnership(msg.sender, false, false);

        _init(underlyingONE);
    }

    function onERC721Received(address from, address, uint256 _id, bytes calldata data)
        external
        override
        returns (bytes4)
    {
        IPaprController.OnERC721ReceivedArgs memory request = abi.decode(data, (IPaprController.OnERC721ReceivedArgs));

        IPaprController.Collateral memory collateral = IPaprController.Collateral(ERC721(msg.sender), _id);

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
        address proceedsTo
    ) public returns (uint256 out) {
        ReservoirOracleUnderwriter.OracleInfo memory dummyInfo;
        out = _swap(
            proceedsTo,
            token0IsUnderlying,
            underlyingAmount,
            minOut,
            sqrtPriceLimitX96,
            abi.encode(account, collateralAsset, msg.sender, dummyInfo)
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

    function addCollateral(IPaprController.Collateral[] calldata collateralArr) public {
        for(uint i = 0; i < collateralArr.length;) {
            IPaprController.Collateral memory collateral = collateralArr[i];
            _addCollateralToVault(msg.sender, collateral);
            collateral.addr.transferFrom(msg.sender, address(this), collateral.id);
            unchecked {
                ++i;
            }
        }
    }

    /// Alternative to using safeTransferFrom,
    /// allows for loan to buy flows
    /// @dev anyone could use this method to add collateral to anyone else's vault
    /// we think this is acceptable and it is useful so that a periphery contract
    /// can modify the tx.origin's vault
    function addCollateralWithCallback(address account, IPaprController.Collateral[] calldata collateralArr, bytes calldata data) public {
        for(uint i = 0; i < collateralArr.length;) {
            IPaprController.Collateral memory collateral = collateralArr[i];
            if (collateral.addr.ownerOf(collateral.id) == address(this)) {
                revert();
            }
            _addCollateralToVault(account, collateral);
            IPostCollateralCallback(msg.sender).postCollateralCallback(collateral, data);
            if (collateral.addr.ownerOf(collateral.id) != address(this)) {
                revert();
            }
            unchecked {
                ++i;
            }
        }
    }

    function removeCollateral(
        address sendTo,
        IPaprController.Collateral calldata collateral,
        ReservoirOracleUnderwriter.OracleInfo calldata oracleInfo
    ) external {
        if (collateralOwner[collateral.addr][collateral.id] != msg.sender) {
            revert IPaprController.OnlyCollateralOwner();
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
            revert IPaprController.ExceedsMaxDebt(debt, max);
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
        // TODO consider clearing latestAuctionStartTime if this is the most recent auction
        // need to check auctionStartTime() which means hashing auction to get ID, gas kind
        // of annoying

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

        PaprToken(address(perpetual)).burn(address(this), fee);

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
        IPaprController.Collateral calldata collateral,
        ReservoirOracleUnderwriter.OracleInfo calldata oracleInfo
    ) public returns (INFTEDA.Auction memory auction) {
        uint256 norm = updateNormalization();

        IPaprController.VaultInfo storage info = _vaultInfo[account][collateral.addr];

        // check collateral belongs to account
        if (collateralOwner[collateral.addr][collateral.id] != account) {
            revert IPaprController.InvalidCollateralAccountPair();
        }

        uint256 oraclePrice =
            underwritePriceForCollateral(collateral.addr, ReservoirOracleUnderwriter.PriceKind.TWAP, oracleInfo);
        if (info.debt < maxDebt(oraclePrice * info.count)) {
            revert IPaprController.NotLiquidatable();
        }

        if (block.timestamp - info.latestAuctionStartTime < liquidationAuctionMinSpacing) {
            revert IPaprController.MinAuctionSpacing();
        }

        info.latestAuctionStartTime = uint40(block.timestamp);
        info.count -= 1;

        emit RemoveCollateral(account, collateral);

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
            revert IPaprController.AccountHasNoDebt();
        } else {
            uint256 maxLoanUnderlying = _vaultInfo[account][asset].count * collateralPrice * maxLTV;
            return maxLoanUnderlying / debt;
        }
    }

    function maxDebt(uint256 totalCollateraValue) public view returns (uint256) {
        uint256 maxLoanUnderlying = totalCollateraValue * maxLTV;
        return maxLoanUnderlying / target;
    }

    function vaultTotalCollateralValue(address account, ERC721 asset, uint256 price) public view returns (uint256) {
        return _vaultInfo[account][asset].count * price;
    }

    function vaultInfo(address account, ERC721 asset) public view returns (IPaprController.VaultInfo memory) {
        return _vaultInfo[account][asset];
    }

    function setAllowedCollateral(IPaprController.SetAllowedCollateralArg[] calldata args) public onlyOwner {
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
            revert IPaprController.TooLittleOut(out, minOut);
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
            revert IPaprController.ExceedsMaxDebt(newDebt, max);
        }

        // TODO safeCast
        _vaultInfo[account][asset].debt = uint200(newDebt);
        PaprToken(address(perpetual)).mint(mintTo, amount);

        emit IncreaseDebt(account, asset, amount);
    }

    function _addCollateralToVault(address account, IPaprController.Collateral memory collateral) internal {
        if (!isAllowed[address(collateral.addr)]) {
            revert IPaprController.InvalidCollateral();
        }

        collateralOwner[collateral.addr][collateral.id] = account;
        _vaultInfo[account][collateral.addr].count += 1;

        emit AddCollateral(account, collateral);
    }

    function _reduceDebt(address account, ERC721 asset, address burnFrom, uint256 amount) internal {
        _reduceDebtWithoutBurn(account, asset, amount);
        PaprToken(address(perpetual)).burn(burnFrom, amount);
    }

    function _reduceDebtWithoutBurn(address account, ERC721 asset, uint256 amount) internal {
        _vaultInfo[account][asset].debt = uint200(_vaultInfo[account][asset].debt - amount);
        emit ReduceDebt(account, asset, amount);
    }
}
