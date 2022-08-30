// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC721, ERC721TokenReceiver} from "solmate/tokens/ERC721.sol";
import {IUniswapV3Factory} from
    "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {TickMath} from "fullrange/libraries/TickMath.sol";

import {StrategyFactory} from "./StrategyFactory.sol";
import {DebtToken} from "./DebtToken.sol";
import {DebtVault} from "./DebtVault.sol";
import {Multicall} from "src/core/base/Multicall.sol";
import {FixedPointMathLib} from "src/libraries/FixedPointMathLib.sol";
import {IPostCollateralCallback} from
    "src/interfaces/IPostCollateralCallback.sol";
import {ILendingStrategy} from "src/interfaces/IPostCollateralCallback.sol";
import {OracleLibrary} from "src/squeeth/OracleLibrary.sol";

contract LendingStrategy is ERC721TokenReceiver, Multicall {
    uint256 constant ONE = 1e18;
    bool public immutable token0IsUnderlying;
    uint256 immutable start;
    uint256 public immutable maxLTV;
    uint256 public immutable targetAPR;
    string public name;
    string public symbol;
    ERC20 public immutable underlying;
    uint256 public PERIOD = 4 weeks;
    uint256 public targetGrowthPerPeriod;
    uint128 public normalization;
    uint128 public lastUpdated;
    DebtToken public debtToken;
    DebtVault public debtVault;
    bytes32 public allowedCollateralRoot;
    IUniswapV3Pool public pool;
    uint256 _nonce;
    int56 lastCumulativeTick;

    // id => vault info
    mapping(uint256 => ILendingStrategy.VaultInfo) public vaultInfo;
    mapping(bytes32 => uint256) public price;

    event DebtAdded(uint256 indexed vaultId, uint256 amount);
    event CollateralAdded(
        uint256 indexed vaultId,
        ILendingStrategy.Collateral collateral,
        ILendingStrategy.OracleInfo oracleInfo
    );
    event DebtReduced(uint256 indexed vaultId, uint256 amount);
    event VaultClosed(uint256 indexed vaultId);
    event NormalizationFactorUpdated(uint128 oldNorm, uint128 newNorm);

    modifier onlyVaultOwner(uint256 vaultId) {
        if (msg.sender != debtVault.ownerOf(vaultId)) {
            revert("only owner");
        }
        _;
    }

    constructor() {
        (name, symbol, allowedCollateralRoot, targetAPR, maxLTV, underlying) =
            StrategyFactory(msg.sender).parameters();
        targetGrowthPerPeriod = targetAPR / (365 days / PERIOD);
        debtToken = new DebtToken(name, symbol, underlying.symbol());
        debtVault = new DebtVault(name, symbol);

        IUniswapV3Factory factory =
            IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

        pool = IUniswapV3Pool(
            factory.createPool(address(underlying), address(debtToken), 10000)
        );
        pool.initialize(TickMath.getSqrtRatioAtTick(0));
        token0IsUnderlying = pool.token0() == address(underlying);

        start = block.timestamp;
        lastUpdated = uint128(block.timestamp);
        normalization = uint128(FixedPointMathLib.WAD);
        lastCumulativeTick = _latestCumulativeTick();
    }

    function openVault(address mintTo) public returns (uint256 id) {
        id = ++_nonce;
        debtVault.mint(mintTo, id);
    }

    /// Kinda an ugly func, possibly could be orchestrated at periphery
    /// instead, but nice that this allows for borrowers to do it all in a single
    /// tx and low gas
    function onERC721Received(
        address from,
        address,
        uint256 _id,
        bytes calldata data
    )
        external
        override
        returns (bytes4)
    {
        ILendingStrategy.OnERC721ReceivedArgs memory request =
            abi.decode(data, (ILendingStrategy.OnERC721ReceivedArgs));

        ILendingStrategy.Collateral memory collateral =
            ILendingStrategy.Collateral(ERC721(msg.sender), _id);

        if (request.vaultId == 0) {
            request.vaultId = openVault(request.mintVaultTo);
        } else {
            if (debtVault.ownerOf(request.vaultId) != from) {
                revert();
            }
        }

        _addCollateralToVault(
            request.vaultId, collateral, request.oracleInfo, request.sig
        );

        if (request.minOut > 0) {
            mintAndSellDebt(
                request.vaultId,
                request.debt,
                request.minOut,
                request.sqrtPriceLimitX96,
                request.mintDebtOrProceedsTo
            );
        } else if (request.debt > 0) {
            _increaseDebt(
                request.vaultId,
                request.mintDebtOrProceedsTo,
                uint256(request.debt)
            );
        }

        return ERC721TokenReceiver.onERC721Received.selector;
    }

    // debated a lot about whether this should be at the periphery. A bit of extra deploy code to put this in each strategy
    // but it saves some gas (don't have to do pool check), and pretty much everything else
    // can be done with the strategy, so I think it's nice
    function mintAndSellDebt(
        uint256 vaultId,
        int256 debt,
        uint256 minOut,
        uint160 sqrtPriceLimitX96,
        address proceedsTo
    )
        public
    {
        // zeroForOne, true if debt token is token0
        bool zeroForOne = !token0IsUnderlying;
        (int256 amount0, int256 amount1) = pool.swap(
            proceedsTo,
            zeroForOne,
            debt,
            sqrtPriceLimitX96, //sqrtx96
            abi.encode(vaultId)
        );

        uint256 out = uint256(-(zeroForOne ? amount1 : amount0));

        if (out < minOut) {
            revert("too little out");
        }
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata _data
    )
        external
    {
        require(amount0Delta > 0 || amount1Delta > 0); // swaps entirely within 0-liquidity regions are not supported

        if (msg.sender != address(pool)) {
            revert("wrong caller");
        }

        uint256 vaultId = abi.decode(_data, (uint256));

        //determine the amount that needs to be repaid as part of the flashswap
        uint256 amountToPay =
            amount0Delta > 0 ? uint256(amount0Delta) : uint256(amount1Delta);

        _increaseDebt(vaultId, msg.sender, amountToPay);
    }

    /// Alternative to using safeTransferFrom,
    /// allows for loan to buy flows
    function addCollateral(
        uint256 vaultId,
        ILendingStrategy.Collateral calldata collateral,
        ILendingStrategy.OracleInfo calldata oracleInfo,
        ILendingStrategy.Sig calldata sig,
        bytes calldata data
    )
        public
    {
        _addCollateralToVault(vaultId, collateral, oracleInfo, sig);
        IPostCollateralCallback(msg.sender).postCollateralCallback(
            ILendingStrategy.StrategyDefinition(
                allowedCollateralRoot, targetAPR, maxLTV, underlying
            ),
            collateral,
            data
        );
        if (collateral.addr.ownerOf(collateral.id) != address(this)) {
            revert();
        }
    }

    function increaseDebt(uint256 vaultId, address mintTo, uint256 amount)
        public
        onlyVaultOwner(vaultId)
    {
        _increaseDebt(vaultId, mintTo, amount);
    }

    function reduceDebt(uint256 vaultId, uint128 amount) public {
        vaultInfo[vaultId].debt -= amount;
        debtToken.burn(msg.sender, amount);
        emit DebtReduced(vaultId, amount);
    }

    function closeVault(uint256 vaultId) public onlyVaultOwner(vaultId) {
        if (vaultInfo[vaultId].debt != 0) {
            revert("still has debt");
        }

        if (vaultInfo[vaultId].price != 0) {
            revert("vault still has collateral");
        }

        debtVault.burn(vaultId);
        delete vaultInfo[vaultId];

        // TODO allow batch removing of collateral
        // collateral.addr.transferFrom(address(this), msg.sender, collateral.id);

        emit VaultClosed(vaultId);
    }

    function liquidate(uint256 vaultId) public {
        updateNormalization();

        if (normalization < liquidationPrice(vaultId) * ONE) {
            revert("not liquidatable");
        }

        // TODO
        // show start an auction, maybe at like
        // vault.price * 3 => converted to debt vault
        // burn debt used to buy token
    }

    function updateNormalization() public {
        if (lastUpdated == block.timestamp) {
            return;
        }
        uint128 previousNormalization = normalization;
        int56 latestCumulativeTick = _latestCumulativeTick();
        uint128 newNormalization = uint128(_newNorm(latestCumulativeTick));
        lastCumulativeTick = latestCumulativeTick;

        normalization = newNormalization;
        lastUpdated = uint128(block.timestamp);

        emit NormalizationFactorUpdated(previousNormalization, newNormalization);
    }

    function newNorm() public view returns (uint256) {
        return _newNorm(_latestCumulativeTick());
    }

    // what each Debt Token is worth in underlying, according to target growth
    function index() public view returns (uint256) {
        return FixedPointMathLib.divWadDown(block.timestamp - start, PERIOD)
            * targetGrowthPerPeriod / FixedPointMathLib.WAD
            + FixedPointMathLib.WAD;
    }

    function markTwapSinceLastUpdate() public view returns (uint256) {
        return _markTwapSinceLastUpdate(_latestCumulativeTick());
    }

    /// aka norm growth if updated right now,
    /// e.g. a result of 12e17 = 1.2 = 20% growth since lastUpdate
    function multiplier() public view returns (int256) {
        return _multiplier(_latestCumulativeTick());
    }

    // normalization value at liquidation
    // i.e. the debt token:underlying internal contract exchange rate (normalization)
    // at which this vault will be liquidated
    function liquidationPrice(uint256 vaultId) public view returns (uint256) {
        uint256 maxLoanUnderlying = vaultInfo[vaultId].price * maxLTV / ONE;
        return maxLoanUnderlying / vaultInfo[vaultId].debt;
    }

    /// @notice given a supposed asset price (would have to be passed on oracle message to be realized)
    /// returns how much synthDebt could be minted
    function maxDebt(uint256 assetPrice) public view returns (uint256) {
        uint256 maxLoanUnderlying = assetPrice * maxLTV;
        return maxLoanUnderlying / normalization;
    }

    function collateralHash(ILendingStrategy.Collateral memory collateral)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(collateral));
    }

    function _increaseDebt(uint256 vaultId, address mintTo, uint256 amount)
        internal
    {
        updateNormalization();

        // TODO, safe to uint128 ?
        vaultInfo[vaultId].debt += uint128(amount);
        debtToken.mint(mintTo, amount);

        if (vaultInfo[vaultId].debt > maxDebt(vaultInfo[vaultId].price)) {
            revert("too much debt");
        }

        emit DebtAdded(vaultId, amount);
    }

    function _addCollateralToVault(
        uint256 vaultId,
        ILendingStrategy.Collateral memory collateral,
        ILendingStrategy.OracleInfo memory oracleInfo,
        ILendingStrategy.Sig memory sig
    )
        internal
    {
        bytes32 h = collateralHash(collateral);

        if (price[h] != 0) {
            // collateral is already here
            revert();
        }

        if (oracleInfo.price == 0) {
            revert();
        }

        // TODO check signature
        // TODO check collateral is allowed in this strategy

        /// TODO re multiple nfts in a single vault
        /// for now we can just add their oracle prices together
        /// but this doesn't work well for strategies in the future
        /// that might have a maxLTV unique to each NFT, if we want
        /// to allow for that
        vaultInfo[vaultId].price += oracleInfo.price;

        emit CollateralAdded(vaultId, collateral, oracleInfo);
    }

    function _newNorm(int56 latestCumulativeTick)
        internal
        view
        returns (uint256)
    {
        return FixedPointMathLib.mulWadDown(normalization, uint256(multiplier()));
    }

    function _markTwapSinceLastUpdate(int56 latestCumulativeTick)
        internal
        view
        returns (uint256)
    {
        uint256 delta = block.timestamp - lastUpdated;
        if (delta == 0) {
            return OracleLibrary.getQuoteAtTick(
                int24(latestCumulativeTick),
                1e18,
                address(debtToken),
                address(underlying)
            );
        } else {
            int24 twapTick = _timeWeightedAverageTick(
                lastCumulativeTick, latestCumulativeTick, int56(uint56(delta))
            );
            return OracleLibrary.getQuoteAtTick(
                twapTick, 1e18, address(debtToken), address(underlying)
            );
        }
    }

    function _multiplier(int56 latestCumulativeTick)
        internal
        view
        returns (int256)
    {
        uint256 m = _markTwapSinceLastUpdate(latestCumulativeTick);
        // TODO: do we need signed ints? when does powWAD return a negative?
        uint256 period = block.timestamp - lastUpdated;
        uint256 periodRatio = FixedPointMathLib.divWadDown(period, PERIOD);
        uint256 targetGrowth = FixedPointMathLib.mulWadDown(
            targetGrowthPerPeriod, periodRatio
        ) + FixedPointMathLib.WAD;
        uint256 indexMarkRatio;
        if (m == 0) {
            indexMarkRatio = 14e17;
        } else {
            indexMarkRatio = FixedPointMathLib.divWadDown(index(), m);
            // cap at 140%, floor at 80%
            if (indexMarkRatio > 14e17) {
                indexMarkRatio = 14e17;
            } else if (indexMarkRatio < 8e17) {
                indexMarkRatio = 8e17;
            }
        }

        /// accelerate or deccelerate apprecation based in index/mark. If mark is too high, slow down. If mark is too low, speed up.
        int256 deviationMultiplier =
            FixedPointMathLib.powWad(int256(indexMarkRatio), int256(periodRatio));

        return deviationMultiplier * int256(targetGrowth)
            / int256(FixedPointMathLib.WAD);
    }

    function _timeWeightedAverageTick(
        int56 startTick,
        int56 endTick,
        int56 twapDuration
    )
        internal
        view
        returns (int24 timeWeightedAverageTick)
    {
        int56 delta = endTick - startTick;

        timeWeightedAverageTick = int24(delta / twapDuration);

        // Always round to negative infinity
        if (delta < 0 && (delta % (twapDuration) != 0)) {
            timeWeightedAverageTick--;
        }

        return timeWeightedAverageTick;
    }

    function _latestCumulativeTick() internal view returns (int56) {
        uint32[] memory secondAgos = new uint32[](1);
        secondAgos[0] = 0;
        (int56[] memory tickCumulatives,) = pool.observe(secondAgos);
        return tickCumulatives[0];
    }
}
