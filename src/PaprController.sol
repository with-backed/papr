// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC721, ERC721TokenReceiver} from "solmate/tokens/ERC721.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {INFTEDA, NFTEDAStarterIncentive} from "NFTEDA/extensions/NFTEDAStarterIncentive.sol";
import {Ownable2Step} from "openzeppelin-contracts/access/Ownable2Step.sol";

import {PaprToken} from "./PaprToken.sol";
import {FundingRateController} from "./FundingRateController.sol";
import {Multicall} from "src/base/Multicall.sol";
import {ReservoirOracleUnderwriter} from "src/ReservoirOracleUnderwriter.sol";
import {IPaprController} from "src/interfaces/IPaprController.sol";
import {UniswapHelpers} from "src/libraries/UniswapHelpers.sol";

contract PaprController is
    FundingRateController,
    ERC721TokenReceiver,
    Multicall,
    Ownable2Step,
    ReservoirOracleUnderwriter,
    NFTEDAStarterIncentive
{
    bool public immutable token0IsUnderlying;
    uint256 public immutable maxLTV;

    // auction configs
    uint256 public liquidationAuctionMinSpacing = 2 days;
    uint256 public perPeriodAuctionDecayWAD = 0.7e18;
    uint256 public auctionDecayPeriod = 1 days;
    uint256 public auctionStartPriceMultiplier = 3;
    uint256 public liquidationPenaltyBips = 1000;

    // account => asset => vaultInfo
    mapping(address => mapping(ERC721 => IPaprController.VaultInfo)) private _vaultInfo;
    // nft address => tokenId => account
    mapping(ERC721 => mapping(uint256 => address)) public collateralOwner;
    // nft address => whether this controller allows as collateral
    mapping(address => bool) public isAllowed;

    event IncreaseDebt(address indexed account, ERC721 indexed collateralAddress, uint256 amount);
    event AddCollateral(address indexed account, IPaprController.Collateral collateral);
    event ReduceDebt(address indexed account, ERC721 indexed collateralAddress, uint256 amount);
    event RemoveCollateral(address indexed account, IPaprController.Collateral collateral);
    event AllowCollateral(address indexed collateral, bool isAllowed);

    constructor(
        string memory name,
        string memory symbol,
        uint256 _maxLTV,
        uint256 indexMarkRatioMax,
        uint256 indexMarkRatioMin,
        ERC20 underlying,
        address oracleSigner
    )
        NFTEDAStarterIncentive(1e17)
        FundingRateController(underlying, new PaprToken(name, symbol), indexMarkRatioMax, indexMarkRatioMin)
        ReservoirOracleUnderwriter(oracleSigner, address(underlying))
    {
        maxLTV = _maxLTV;
        token0IsUnderlying = address(underlying) < address(papr);
        uint256 underlyingONE = 10 ** underlying.decimals();
        uint160 sqrtRatio;

        // initialize the pool at 1:1
        if (token0IsUnderlying) {
            sqrtRatio = UniswapHelpers.oneToOneSqrtRatio(underlyingONE, 10 ** 18);
        } else {
            sqrtRatio = UniswapHelpers.oneToOneSqrtRatio(10 ** 18, underlyingONE);
        }

        _init(underlyingONE, sqrtRatio);
    }

    function onERC721Received(address from, address, uint256 _id, bytes calldata data)
        external
        override
        returns (bytes4)
    {
        IPaprController.OnERC721ReceivedArgs memory request = abi.decode(data, (IPaprController.OnERC721ReceivedArgs));

        IPaprController.Collateral memory collateral = IPaprController.Collateral(ERC721(msg.sender), _id);

        _addCollateralToVault(from, collateral);

        if (request.swapParams.minOut > 0) {
            _increaseDebtAndSell(from, request.proceedsTo, ERC721(msg.sender), request.swapParams, request.oracleInfo);
        } else if (request.debt > 0) {
            _increaseDebt(from, collateral.addr, request.proceedsTo, request.debt, request.oracleInfo);
        }

        return ERC721TokenReceiver.onERC721Received.selector;
    }

    function increaseDebtAndSell(
        address proceedsTo,
        ERC721 collateralAsset,
        IPaprController.SwapParams calldata params,
        ReservoirOracleUnderwriter.OracleInfo calldata oracleInfo
    ) public returns (uint256 amountOut) {
        bool hasFee = params.swapFeeBips != 0;

        (amountOut,) = UniswapHelpers.swap(
            pool,
            hasFee ? address(this) : proceedsTo,
            !token0IsUnderlying,
            params.amount,
            params.minOut,
            params.sqrtPriceLimitX96,
            abi.encode(msg.sender, collateralAsset, oracleInfo)
        );

        if (hasFee) {
            uint256 fee = amountOut * params.swapFeeBips / 1e4;
            underlying.transfer(params.swapFeeTo, fee);
            underlying.transfer(proceedsTo, amountOut - fee);
        }
    }

    function buyAndReduceDebt(address account, ERC721 collateralAsset, IPaprController.SwapParams calldata params)
        public
        returns (uint256)
    {
        bool hasFee = params.swapFeeBips != 0;

        (uint256 amountOut, uint256 amountIn) = UniswapHelpers.swap(
            pool,
            account,
            token0IsUnderlying,
            params.amount,
            params.minOut,
            params.sqrtPriceLimitX96,
            abi.encode(msg.sender)
        );

        if (hasFee) {
            underlying.transfer(params.swapFeeTo, amountIn * params.swapFeeBips / 1e4);
        }

        reduceDebt(account, collateralAsset, uint96(amountOut));

        return amountOut;
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata _data) external {
        if (msg.sender != address(pool)) {
            revert("wrong caller");
        }

        bool isUnderlyingIn;
        uint256 amountToPay;
        if (amount0Delta > 0) {
            amountToPay = uint256(amount0Delta);
            isUnderlyingIn = token0IsUnderlying;
        } else {
            require(amount1Delta > 0); // swaps entirely within 0-liquidity regions are not supported

            amountToPay = uint256(amount1Delta);
            isUnderlyingIn = !(token0IsUnderlying);
        }

        if (isUnderlyingIn) {
            address payer = abi.decode(_data, (address));
            underlying.transferFrom(payer, msg.sender, amountToPay);
        } else {
            (address account, ERC721 asset, ReservoirOracleUnderwriter.OracleInfo memory oracleInfo) =
                abi.decode(_data, (address, ERC721, ReservoirOracleUnderwriter.OracleInfo));
            _increaseDebt(account, asset, msg.sender, amountToPay, oracleInfo);
        }
    }

    function addCollateral(IPaprController.Collateral calldata collateral) public {
        _addCollateralToVault(msg.sender, collateral);
        collateral.addr.transferFrom(msg.sender, address(this), collateral.id);
    }

    function removeCollateral(
        address sendTo,
        IPaprController.Collateral calldata collateral,
        ReservoirOracleUnderwriter.OracleInfo calldata oracleInfo
    ) external {
        uint256 newTarget = updateTarget();

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
        uint256 max = _maxDebt(oraclePrice * newCount, newTarget);

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
        uint256 maxDebtCached = isLastCollateral ? debtCached : _maxDebt(collateralValueCached, updateTarget());
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

    function startLiquidationAuction(
        address account,
        IPaprController.Collateral calldata collateral,
        ReservoirOracleUnderwriter.OracleInfo calldata oracleInfo
    ) public returns (INFTEDA.Auction memory auction) {
        uint256 _target = updateTarget();

        IPaprController.VaultInfo storage info = _vaultInfo[account][collateral.addr];

        // check collateral belongs to account
        if (collateralOwner[collateral.addr][collateral.id] != account) {
            revert IPaprController.InvalidCollateralAccountPair();
        }

        uint256 oraclePrice =
            underwritePriceForCollateral(collateral.addr, ReservoirOracleUnderwriter.PriceKind.TWAP, oracleInfo);
        if (info.debt < _maxDebt(oraclePrice * info.count, _target)) {
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
                // converted to papr value at the current contract price
                startPrice: (oraclePrice * auctionStartPriceMultiplier) * FixedPointMathLib.WAD / _target,
                paymentAsset: papr
            })
        );
    }

    function setPool(address _pool) public onlyOwner {
        _setPool(_pool);
    }

    function setFundingPeriod(uint256 _fundingPeriod) public onlyOwner {
        _setFundingPeriod(_fundingPeriod);
    }

    function setAllowedCollateral(IPaprController.CollateralAllowedConfig[] calldata collateralConfigs)
        external
        onlyOwner
    {
        for (uint256 i = 0; i < collateralConfigs.length;) {
            if (collateralConfigs[i].collateral == address(0)) revert IPaprController.InvalidCollateral();

            isAllowed[collateralConfigs[i].collateral] = collateralConfigs[i].allowed;
            emit AllowCollateral(collateralConfigs[i].collateral, collateralConfigs[i].allowed);
            unchecked {
                ++i;
            }
        }
    }

    /// TODO admin functions: update auction configs, move papr from liquidation fee, update reservoir oracle configs

    function maxDebt(uint256 totalCollateraValue) public view returns (uint256) {
        if (lastUpdated == block.timestamp) {
            return _maxDebt(totalCollateraValue, target);
        }

        return _maxDebt(totalCollateraValue, newTarget());
    }

    function vaultInfo(address account, ERC721 asset) public view returns (IPaprController.VaultInfo memory) {
        return _vaultInfo[account][asset];
    }

    /// same as increaseDebtAndSell but takes args in memory
    /// to work with onERC721Received
    function _increaseDebtAndSell(
        address account,
        address proceedsTo,
        ERC721 collateralAsset,
        IPaprController.SwapParams memory params,
        ReservoirOracleUnderwriter.OracleInfo memory oracleInfo
    ) internal returns (uint256 amountOut) {
        bool hasFee = params.swapFeeBips != 0;

        (amountOut,) = UniswapHelpers.swap(
            pool,
            hasFee ? address(this) : proceedsTo,
            !token0IsUnderlying,
            params.amount,
            params.minOut,
            params.sqrtPriceLimitX96,
            abi.encode(account, collateralAsset, oracleInfo)
        );

        if (hasFee) {
            uint256 fee = amountOut * params.swapFeeBips / 1e4;
            underlying.transfer(params.swapFeeTo, fee);
            underlying.transfer(proceedsTo, amountOut - fee);
        }
    }

    function _increaseDebt(
        address account,
        ERC721 asset,
        address mintTo,
        uint256 amount,
        ReservoirOracleUnderwriter.OracleInfo memory oracleInfo
    ) internal {
        uint256 _target = updateTarget();

        uint256 newDebt = _vaultInfo[account][asset].debt + amount;
        uint256 oraclePrice =
            underwritePriceForCollateral(asset, ReservoirOracleUnderwriter.PriceKind.LOWER, oracleInfo);

        // TODO do we need to check if oraclePrice is 0?

        uint256 max = _maxDebt(_vaultInfo[account][asset].count * oraclePrice, _target);
        if (newDebt > max) {
            revert IPaprController.ExceedsMaxDebt(newDebt, max);
        }

        // TODO safeCast
        _vaultInfo[account][asset].debt = uint200(newDebt);
        PaprToken(address(papr)).mint(mintTo, amount);

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
        PaprToken(address(papr)).burn(burnFrom, amount);
    }

    function _reduceDebtWithoutBurn(address account, ERC721 asset, uint256 amount) internal {
        _vaultInfo[account][asset].debt = uint200(_vaultInfo[account][asset].debt - amount);
        emit ReduceDebt(account, asset, amount);
    }

    function _handleExcess(uint256 excess, uint256 neededToSaveVault, uint256 debtCached, Auction calldata auction)
        internal
        returns (uint256 remaining)
    {
        uint256 fee = excess * liquidationPenaltyBips / 1e4;
        uint256 credit = excess - fee;
        uint256 totalOwed = credit + neededToSaveVault;

        PaprToken(address(papr)).burn(address(this), fee);

        if (totalOwed > debtCached) {
            // we owe them more papr than they have in debt
            // so we pay down debt and send them the rest
            _reduceDebt(auction.nftOwner, auction.auctionAssetContract, address(this), debtCached);
            papr.transfer(auction.nftOwner, totalOwed - debtCached);
        } else {
            // reduce vault debt
            _reduceDebt(auction.nftOwner, auction.auctionAssetContract, address(this), totalOwed);
            remaining = debtCached - totalOwed;
        }
    }

    function _maxDebt(uint256 totalCollateraValue, uint256 _target) internal view returns (uint256) {
        uint256 maxLoanUnderlying = totalCollateraValue * maxLTV;
        return maxLoanUnderlying / _target;
    }
}
