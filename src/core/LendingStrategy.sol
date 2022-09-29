// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC721, ERC721TokenReceiver} from "solmate/tokens/ERC721.sol";
import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {SafeCast} from "v3-core/contracts/libraries/SafeCast.sol";
import {TickMath} from "fullrange/libraries/TickMath.sol";

import {StrategyFactory} from "./StrategyFactory.sol";
import {DebtToken} from "./DebtToken.sol";
import {DebtVault} from "./DebtVault.sol";
import {Multicall} from "src/core/base/Multicall.sol";
import {FixedPointMathLib} from "src/libraries/FixedPointMathLib.sol";
import {IPostCollateralCallback} from "src/interfaces/IPostCollateralCallback.sol";
import {ILendingStrategy} from "src/interfaces/IPostCollateralCallback.sol";
import {OracleLibrary} from "src/squeeth/OracleLibrary.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {BoringOwnable} from "@boringsolidity/BoringOwnable.sol";

contract LendingStrategy is ERC721TokenReceiver, Multicall, BoringOwnable {
    using SafeCast for uint256;

    address public immutable factory;
    bool public immutable token0IsUnderlying;
    uint256 public immutable start;
    uint256 public immutable maxLTV;
    ERC20 public immutable underlying;
    IUniswapV3Pool public immutable pool;
    uint256 public PERIOD = 4 weeks;
    DebtToken public debtToken;
    // DebtVault public debtVault;
    string public strategyURI;
    uint256 _nonce;
    // single slot, write together
    uint128 public normalization;
    uint72 public lastUpdated;
    int56 lastCumulativeTick;

    // id => vault info
    mapping(uint256 => ILendingStrategy.VaultInfo) public vaultInfo;
    mapping(bytes32 => uint256) public collateralFrozenOraclePrice;
    mapping(address => bool) public isAllowed;

    event IncreaseDebt(uint256 indexed vaultId, uint256 amount);
    event AddCollateral(
        uint256 indexed vaultId,
        uint256 vaultNonce,
        ILendingStrategy.Collateral collateral,
        ILendingStrategy.OracleInfo oracleInfo
    );
    event ReduceDebt(uint256 indexed vaultId, uint256 amount);
    event RemoveCollateral(
        uint256 indexed vaultId, ILendingStrategy.Collateral collateral, uint256 vaultCollateralValue
    );
    event UpdateNormalization(uint256 newNorm);
    event ChangeCollateralAllowed(ILendingStrategy.SetAllowedCollateralArg arg);

    constructor() {
        factory = msg.sender;
        string memory name;
        string memory symbol;
        (name, symbol, strategyURI, , maxLTV, underlying) = StrategyFactory(msg.sender).parameters();
        debtToken = new DebtToken(name, symbol, underlying.symbol());

        IUniswapV3Factory factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

        pool = IUniswapV3Pool(factory.createPool(address(underlying), address(debtToken), 10000));
        pool.initialize(TickMath.getSqrtRatioAtTick(0));
        token0IsUnderlying = pool.token0() == address(underlying);

        start = block.timestamp;
    }

    function initialize() external {
        if (msg.sender != factory) {
            revert();
        }

        if (normalization != 0) {
            revert();
        }

        lastUpdated = uint72(block.timestamp);
        normalization = uint128(FixedPointMathLib.WAD);
        lastCumulativeTick = _latestCumulativeTick();

        emit UpdateNormalization(FixedPointMathLib.WAD);
    }

    function onERC721Received(address from, address, uint256 _id, bytes calldata data)
        external
        override
        returns (bytes4)
    {
        ILendingStrategy.OnERC721ReceivedArgs memory request = abi.decode(data, (ILendingStrategy.OnERC721ReceivedArgs));

        ILendingStrategy.Collateral memory collateral = ILendingStrategy.Collateral(ERC721(msg.sender), _id);

        uint256 vaultId = vaultIdentifier(request.vaultNonce, from);

        _addCollateralToVault(vaultId, request.vaultNonce, collateral, request.oracleInfo, request.sig);

        if (request.minOut > 0) {
            _swap(
                request.mintDebtOrProceedsTo,
                !token0IsUnderlying,
                request.debt,
                request.minOut,
                request.sqrtPriceLimitX96,
                abi.encode(vaultId, address(this))
            );
        } else if (request.debt > 0) {
            _increaseDebt(vaultId, request.mintDebtOrProceedsTo, uint256(request.debt));
        }

        return ERC721TokenReceiver.onERC721Received.selector;
    }

    /// TODO consider passing token0IsUnderlying to save an SLOAD
    function mintAndSellDebt(
        uint256 vaultNonce,
        uint256 debt,
        uint256 minOut,
        uint160 sqrtPriceLimitX96,
        address proceedsTo
    ) public returns (uint256) {
        return _swap(
            proceedsTo,
            !token0IsUnderlying,
            debt,
            minOut,
            sqrtPriceLimitX96,
            abi.encode(vaultIdentifier(vaultNonce, msg.sender), address(this))
        );
    }

    function buyAndReduceDebt(
        uint256 vaultId,
        uint256 underlyingAmount,
        uint256 minOut,
        uint160 sqrtPriceLimitX96,
        address proceedsTo
    ) public returns (uint256 out) {
        out = _swap(
            proceedsTo, token0IsUnderlying, underlyingAmount, minOut, sqrtPriceLimitX96, abi.encode(vaultId, msg.sender)
        );
        reduceDebt(vaultId, uint128(out));
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata _data) external {
        require(amount0Delta > 0 || amount1Delta > 0); // swaps entirely within 0-liquidity regions are not supported

        if (msg.sender != address(pool)) {
            revert("wrong caller");
        }

        (uint256 vaultId, address payer) = abi.decode(_data, (uint256, address));

        //determine the amount that needs to be repaid as part of the flashswap
        uint256 amountToPay = amount0Delta > 0 ? uint256(amount0Delta) : uint256(amount1Delta);

        if (payer == address(this)) {
            _increaseDebt(vaultId, msg.sender, amountToPay);
        } else {
            underlying.transferFrom(payer, msg.sender, amountToPay);
        }
    }

    function addCollateral(
        uint256 vaultNonce,
        ILendingStrategy.Collateral calldata collateral,
        ILendingStrategy.OracleInfo calldata oracleInfo,
        ILendingStrategy.Sig calldata sig
    ) public {
        uint256 vaultId = vaultIdentifier(vaultNonce, msg.sender);
        _addCollateralToVault(vaultId, vaultNonce, collateral, oracleInfo, sig);
        collateral.addr.transferFrom(msg.sender, address(this), collateral.id);
    }

    /// Alternative to using safeTransferFrom,
    /// allows for loan to buy flows
    /// @dev anyone could use this method to add collateral to anyone else's vault
    /// we think this is acceptable and it is useful so that a periphery contract
    /// can modify the tx.origin's vault
    function addCollateralWithCallback(
        uint256 vaultNonce,
        address vaultOwner,
        ILendingStrategy.Collateral calldata collateral,
        ILendingStrategy.OracleInfo calldata oracleInfo,
        ILendingStrategy.Sig calldata sig,
        bytes calldata data
    ) public {
        uint256 vaultId = vaultIdentifier(vaultNonce, vaultOwner);
        _addCollateralToVault(vaultId, vaultNonce, collateral, oracleInfo, sig);
        IPostCollateralCallback(msg.sender).postCollateralCallback(
            ILendingStrategy.StrategyDefinition(0, maxLTV, underlying), collateral, data
        );
        if (collateral.addr.ownerOf(collateral.id) != address(this)) {
            revert();
        }
    }

    function removeCollateral(address sendTo, uint256 vaultNonce, ILendingStrategy.Collateral calldata collateral)
        external
    {
        uint256 vaultId = vaultIdentifier(vaultNonce, msg.sender);
        bytes32 h = collateralHash(collateral, vaultId);
        uint256 price = collateralFrozenOraclePrice[h];

        if (price == 0) {
            revert ILendingStrategy.InvalidCollateralVaultIDCombination();
        }

        delete collateralFrozenOraclePrice[h];
        uint256 newVaultCollateralValue = vaultInfo[vaultId].collateralValue - price;
        vaultInfo[vaultId].collateralValue = uint128(newVaultCollateralValue);

        // allows for onReceive hook to sell and repay debt before the
        // debt check below
        collateral.addr.safeTransferFrom(address(this), sendTo, collateral.id);

        uint256 debt = vaultInfo[vaultId].debt;
        uint256 max = maxDebt(newVaultCollateralValue);

        if (debt > max) {
            revert ILendingStrategy.ExceedsMaxDebt(debt, max);
        }

        emit RemoveCollateral(vaultId, collateral, newVaultCollateralValue);
    }

    function increaseDebt(uint256 vaultNonce, address mintTo, uint256 amount) public {
        _increaseDebt(vaultIdentifier(vaultNonce, msg.sender), mintTo, amount);
    }

    function reduceDebt(uint256 vaultId, uint128 amount) public {
        vaultInfo[vaultId].debt -= amount;
        debtToken.burn(msg.sender, amount);
        emit ReduceDebt(vaultId, amount);
    }

    function liquidate(uint256 vaultId) public {
        updateNormalization();

        if (normalization < liquidationPrice(vaultId) * FixedPointMathLib.WAD) {
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
        uint256 newNormalization = _newNorm(latestCumulativeTick, previousNormalization);

        normalization = uint128(newNormalization);
        lastUpdated = uint72(block.timestamp);
        lastCumulativeTick = latestCumulativeTick;

        emit UpdateNormalization(newNormalization);
    }

    function newNorm() public view returns (uint256) {
        return _newNorm(_latestCumulativeTick(), normalization);
    }

    // what each Debt Token is worth in underlying, according to target growth
    function index() public view returns (uint256) {
        return 1;
    }

    function markTwapSinceLastUpdate() public view returns (uint256) {
        return _markTwapSinceLastUpdate(_latestCumulativeTick());
    }

    /// aka norm growth if updated right now,
    /// e.g. a result of 12e17 = 1.2 = 20% growth since lastUpdate
    function multiplier() public view returns (int256) {
        return _multiplier(_latestCumulativeTick(), normalization);
    }

    // normalization value at liquidation
    // i.e. the debt token:underlying internal contract exchange rate (normalization)
    // at which this vault will be liquidated
    function liquidationPrice(uint256 vaultId) public view returns (uint256) {
        uint256 maxLoanUnderlying = FixedPointMathLib.mulWadDown(vaultInfo[vaultId].collateralValue, maxLTV);
        return maxLoanUnderlying / vaultInfo[vaultId].debt;
    }

    function maxDebt(uint256 collateralValue) public view returns (uint256) {
        uint256 maxLoanUnderlying = collateralValue * maxLTV;
        return maxLoanUnderlying / normalization;
    }

    function collateralHash(ILendingStrategy.Collateral memory collateral, uint256 vaultId)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(collateral, vaultId));
    }

    function vaultIdentifier(uint256 nonce, address account) public view returns (uint256) {
        return uint256(keccak256(abi.encode(nonce, account)));
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

    function _increaseDebt(uint256 vaultId, address mintTo, uint256 amount) internal {
        updateNormalization();

        // TODO, safe to uint128 ?
        vaultInfo[vaultId].debt += uint128(amount);
        debtToken.mint(mintTo, amount);

        uint256 debt = vaultInfo[vaultId].debt;
        uint256 max = maxDebt(vaultInfo[vaultId].collateralValue);
        if (debt > max) {
            revert ILendingStrategy.ExceedsMaxDebt(debt, max);
        }

        emit IncreaseDebt(vaultId, amount);
    }

    function _addCollateralToVault(
        uint256 vaultId,
        uint256 vaultNonce,
        ILendingStrategy.Collateral memory collateral,
        ILendingStrategy.OracleInfo memory oracleInfo,
        ILendingStrategy.Sig memory sig
    ) internal {
        bytes32 h = collateralHash(collateral, vaultId);

        if (collateralFrozenOraclePrice[h] != 0) {
            // collateral is already here
            revert();
        }

        if (oracleInfo.price == 0) {
            revert();
        }

        // TODO check signature
        // TODO check collateral is allowed in this strategy
        if (!isAllowed[address(collateral.addr)]) {
            revert ILendingStrategy.InvalidCollateral();
        }

        collateralFrozenOraclePrice[h] = oracleInfo.price;
        vaultInfo[vaultId].collateralValue += oracleInfo.price;

        emit AddCollateral(vaultId, vaultNonce, collateral, oracleInfo);
    }

    function _newNorm(int56 latestCumulativeTick, uint256 cachedNorm) internal view returns (uint256) {
        return FixedPointMathLib.mulWadDown(normalization, uint256(_multiplier(latestCumulativeTick, cachedNorm)));
    }

    function _markTwapSinceLastUpdate(int56 latestCumulativeTick) internal view returns (uint256) {
        uint256 delta = block.timestamp - lastUpdated;
        if (delta == 0) {
            return OracleLibrary.getQuoteAtTick(
                int24(latestCumulativeTick), 1e18, address(debtToken), address(underlying)
            );
        } else {
            int24 twapTick = _timeWeightedAverageTick(lastCumulativeTick, latestCumulativeTick, int56(uint56(delta)));
            return OracleLibrary.getQuoteAtTick(twapTick, 1e18, address(debtToken), address(underlying));
        }
    }

    function _multiplier(int56 latestCumulativeTick, uint256 cachedNorm) internal view returns (int256) {
        uint256 m = _markTwapSinceLastUpdate(latestCumulativeTick);
        uint256 period = block.timestamp - lastUpdated;
        uint256 periodRatio = FixedPointMathLib.divWadDown(period, PERIOD);
        uint256 indexMarkRatio;
        if (m == 0) {
            indexMarkRatio = 14e17;
        } else {
            indexMarkRatio = FixedPointMathLib.divWadDown(index(), FixedPointMathLib.divWadDown(m, cachedNorm));
            // cap at 140%, floor at 80%
            if (indexMarkRatio > 14e17) {
                indexMarkRatio = 14e17;
            } else if (indexMarkRatio < 8e17) {
                indexMarkRatio = 8e17;
            }
        }

        return FixedPointMathLib.powWad(int256(indexMarkRatio), int256(periodRatio));
    }

    function _timeWeightedAverageTick(int56 startTick, int56 endTick, int56 twapDuration)
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
