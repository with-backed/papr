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
    uint256 perPeriodAuctionDecayWAD = 0.7e18;
    uint256 auctionDecayPeriod = 1 days;
    uint256 auctionStartPriceMultiplier = 3;
    uint256 public liquidationPenaltyBips = 1000;

    mapping(address => ILendingStrategy.VaultInfo) private _vaultInfo;
    mapping(bytes32 => uint256) public collateralFrozenOraclePrice;
    mapping(address => bool) public isAllowed;

    event IncreaseDebt(address indexed account, uint256 amount);
    event AddCollateral(address indexed account, ILendingStrategy.Collateral collateral, uint256 price);
    event ReduceDebt(address indexed account, uint256 amount);
    event RemoveCollateral(
        address indexed account, ILendingStrategy.Collateral collateral, uint256 vaultCollateralValue
    );

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

        _addCollateralToVault(from, collateral, request.oracleInfo);

        if (request.minOut > 0) {
            _swap(
                request.mintDebtOrProceedsTo,
                !token0IsUnderlying,
                request.debt,
                request.minOut,
                request.sqrtPriceLimitX96,
                abi.encode(from, address(this))
            );
        } else if (request.debt > 0) {
            _increaseDebt(from, request.mintDebtOrProceedsTo, uint256(request.debt));
        }

        return ERC721TokenReceiver.onERC721Received.selector;
    }

    /// TODO consider passing token0IsUnderlying to save an SLOAD
    function mintAndSellDebt(uint256 debt, uint256 minOut, uint160 sqrtPriceLimitX96, address proceedsTo)
        public
        returns (uint256)
    {
        return _swap(
            proceedsTo, !token0IsUnderlying, debt, minOut, sqrtPriceLimitX96, abi.encode(msg.sender, address(this))
        );
    }

    function buyAndReduceDebt(
        address account,
        uint256 underlyingAmount,
        uint256 minOut,
        uint160 sqrtPriceLimitX96,
        address proceedsTo
    ) public returns (uint256 out) {
        out = _swap(
            proceedsTo, token0IsUnderlying, underlyingAmount, minOut, sqrtPriceLimitX96, abi.encode(account, msg.sender)
        );
        reduceDebt(account, uint96(out));
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata _data) external {
        require(amount0Delta > 0 || amount1Delta > 0); // swaps entirely within 0-liquidity regions are not supported

        if (msg.sender != address(pool)) {
            revert("wrong caller");
        }

        (address account, address payer) = abi.decode(_data, (address, address));

        //determine the amount that needs to be repaid as part of the flashswap
        uint256 amountToPay = amount0Delta > 0 ? uint256(amount0Delta) : uint256(amount1Delta);

        if (payer == address(this)) {
            _increaseDebt(account, msg.sender, amountToPay);
        } else {
            underlying.transferFrom(payer, msg.sender, amountToPay);
        }
    }

    function addCollateral(
        ILendingStrategy.Collateral calldata collateral,
        ReservoirOracleUnderwriter.OracleInfo calldata oracleInfo
    ) public {
        _addCollateralToVault(msg.sender, collateral, oracleInfo);
        collateral.addr.transferFrom(msg.sender, address(this), collateral.id);
    }

    /// Alternative to using safeTransferFrom,
    /// allows for loan to buy flows
    /// @dev anyone could use this method to add collateral to anyone else's vault
    /// we think this is acceptable and it is useful so that a periphery contract
    /// can modify the tx.origin's vault
    function addCollateralWithCallback(
        ILendingStrategy.Collateral calldata collateral,
        ReservoirOracleUnderwriter.OracleInfo calldata oracleInfo,
        bytes calldata data
    ) public {
        if (collateral.addr.ownerOf(collateral.id) == address(this)) {
            revert();
        }
        _addCollateralToVault(msg.sender, collateral, oracleInfo);
        IPostCollateralCallback(msg.sender).postCollateralCallback(collateral, data);
        if (collateral.addr.ownerOf(collateral.id) != address(this)) {
            revert();
        }
    }

    function removeCollateral(address sendTo, ILendingStrategy.Collateral calldata collateral) external {
        bytes32 h = collateralHash(collateral, msg.sender);
        uint256 price = collateralFrozenOraclePrice[h];

        if (price == 0) {
            revert ILendingStrategy.InvalidCollateralVaultIDCombination();
        }

        delete collateralFrozenOraclePrice[h];
        uint256 newVaultCollateralValue = _vaultInfo[msg.sender].collateralValue - price;
        _vaultInfo[msg.sender].collateralValue = uint96(newVaultCollateralValue);

        // allows for onReceive hook to sell and repay debt before the
        // debt check below
        collateral.addr.safeTransferFrom(address(this), sendTo, collateral.id);

        uint256 debt = _vaultInfo[msg.sender].debt;
        uint256 max = maxDebt(newVaultCollateralValue);

        if (debt > max) {
            revert ILendingStrategy.ExceedsMaxDebt(debt, max);
        }

        emit RemoveCollateral(msg.sender, collateral, newVaultCollateralValue);
    }

    function increaseDebt(address mintTo, uint256 amount) public {
        _increaseDebt(msg.sender, mintTo, amount);
    }

    function reduceDebt(address account, uint256 amount) public {
        _reduceDebt(account, msg.sender, amount);
    }

    function _reduceDebt(address account, address burnFrom, uint256 amount) internal {
        _reduceDebtWithoutBurn(account, amount);
        DebtToken(address(perpetual)).burn(burnFrom, amount);
        
    }

    function _reduceDebtWithoutBurn(address account, uint256 amount) internal {
        _vaultInfo[account].debt -= uint96(amount);
        emit ReduceDebt(account, amount);
    }

    function purchaseLiquidationAuctionNFT(Auction calldata auction, uint256 maxPrice, address sendTo) public {
        uint256 collateralValueCached = _vaultInfo[auction.nftOwner].collateralValue;
        bool isLastCollateral = collateralValueCached == 0;
        
        uint256 debtCached = _vaultInfo[auction.nftOwner].debt;
        uint256 maxDebtCached = maxDebt(_vaultInfo[auction.nftOwner].collateralValue);
        /// If this is the last NFT, then excess is anything above the debt's value
        /// if this is not the last NFT, excess is anything beyond what needs to be paid to 
        /// go back under maxDebt
        uint256 breakEven = isLastCollateral ? debtCached : (maxDebtCached > debtCached ? 0 : debtCached - maxDebtCached);
        uint256 price = _purchaseNFT(auction, maxPrice, sendTo);
        uint256 excess = price > breakEven ? price - breakEven : 0;

        if (excess != 0) {
            uint256 fee = excess * liquidationPenaltyBips / 1e4;
            uint256 credit = excess - fee;
            uint256 totalOwed = credit + breakEven;
            if (totalOwed > debtCached) {
                // we owe them more papr than they have in debt
                // so we pay down debt and send them the rest
                _reduceDebt(auction.nftOwner, address(this),  breakEven);
                perpetual.transfer(auction.nftOwner, totalOwed - breakEven);
            } else { 
                // reduce vault debt
                _reduceDebt(auction.nftOwner, address(this), totalOwed);
            }
        } else {
            _reduceDebt(auction.nftOwner, address(this),  price);
        }
        
        if (isLastCollateral && price < breakEven) {
            /// there will be debt left with no NFTs, set it to 0
            _reduceDebtWithoutBurn(auction.nftOwner, price - breakEven);
        }
    }

    function startLiquidationAuction(address account, ILendingStrategy.Collateral calldata collateral) public returns (INFTEDA.Auction memory auction) {
        uint256 norm = updateNormalization();

        ILendingStrategy.VaultInfo storage info = _vaultInfo[account];

        // check collateral belongs to account
        bytes32 h = collateralHash(collateral, account);
        uint256 price = collateralFrozenOraclePrice[h];
        if (price == 0) {
            revert ILendingStrategy.InvalidCollateralAccountPair();
        }

        if (norm < liquidationPrice(account)) {
            revert ILendingStrategy.NotLiquidatable();
        }

        if (block.timestamp - info.latestAuctionStartTime < liquidationAuctionMinSpacing) {
            revert ILendingStrategy.MinAuctionSpacing();
        }

        info.latestAuctionStartTime = uint40(block.timestamp);
        info.collateralValue -= uint96(price);

        delete collateralFrozenOraclePrice[h];

        _startAuction(
            auction = Auction({
                nftOwner: account,
                auctionAssetID: collateral.id,
                auctionAssetContract: collateral.addr,
                perPeriodDecayPercentWad: perPeriodAuctionDecayWAD,
                secondsInPeriod: auctionDecayPeriod,
                // start price is frozen price * auctionStartPriceMultiplier,
                // converted to perpetual value at the current contract price
                startPrice: (price * auctionStartPriceMultiplier) * FixedPointMathLib.WAD / norm,
                paymentAsset: perpetual
            })
        );
    }

    // normalization value at liquidation
    // i.e. the debt token:underlying internal contract exchange rate (normalization)
    // at which this vault will be liquidated
    function liquidationPrice(address account) public view returns (uint256) {
        uint256 maxLoanUnderlying = _vaultInfo[account].collateralValue * maxLTV;
        return maxLoanUnderlying / _vaultInfo[account].debt;
    }

    function maxDebt(uint256 collateralValue) public view returns (uint256) {
        uint256 maxLoanUnderlying = collateralValue * maxLTV;
        return maxLoanUnderlying / normalization;
    }

    function collateralHash(ILendingStrategy.Collateral memory collateral, address account)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(collateral, account));
    }

    function vaultIdentifier(uint256 nonce, address account) public view returns (uint256) {
        return uint256(keccak256(abi.encode(nonce, account)));
    }

    function vaultInfo(address account) public view returns (ILendingStrategy.VaultInfo memory) {
        return _vaultInfo[account];
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

    function _increaseDebt(address account, address mintTo, uint256 amount) internal {
        updateNormalization();

        // TODO, safe to uint96 ?
        _vaultInfo[account].debt += uint96(amount);
        DebtToken(address(perpetual)).mint(mintTo, amount);

        uint256 debt = _vaultInfo[account].debt;
        uint256 max = maxDebt(_vaultInfo[account].collateralValue);
        if (debt > max) {
            revert ILendingStrategy.ExceedsMaxDebt(debt, max);
        }

        emit IncreaseDebt(account, amount);
    }

    function _addCollateralToVault(
        address account,
        ILendingStrategy.Collateral memory collateral,
        ReservoirOracleUnderwriter.OracleInfo memory oracleInfo
    ) internal {
        bytes32 h = collateralHash(collateral, account);
        /// TODO: do we need this check? I think was just for the callback
        /// case but I added a check there that the collateral is not
        /// already in the vault
        if (collateralFrozenOraclePrice[h] != 0) {
            // collateral is already here
            revert();
        }

        if (!isAllowed[address(collateral.addr)]) {
            revert ILendingStrategy.InvalidCollateral();
        }

        uint256 oraclePrice = underwritePriceForCollateral(collateral.id, address(collateral.addr), oracleInfo);

        if (oraclePrice == 0) {
            revert();
        }

        collateralFrozenOraclePrice[h] = oraclePrice;
        _vaultInfo[account].collateralValue += uint96(oraclePrice);

        emit AddCollateral(account, collateral, oraclePrice);
    }
}
