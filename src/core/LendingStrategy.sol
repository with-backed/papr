// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC721, ERC721TokenReceiver} from "solmate/tokens/ERC721.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {SafeCast} from "v3-core/contracts/libraries/SafeCast.sol";
import {TickMath} from "fullrange/libraries/TickMath.sol";

import {DebtToken} from "./DebtToken.sol";
import {LinearPerpetual} from "./LinearPerpetual.sol";
import {Multicall} from "src/core/base/Multicall.sol";
import {IPostCollateralCallback} from "src/interfaces/IPostCollateralCallback.sol";
import {ILendingStrategy} from "src/interfaces/IPostCollateralCallback.sol";
import {OracleLibrary} from "src/libraries/OracleLibrary.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {BoringOwnable} from "@boringsolidity/BoringOwnable.sol";

contract LendingStrategy is LinearPerpetual, ERC721TokenReceiver, Multicall, BoringOwnable {
    using SafeCast for uint256;

    bool public immutable token0IsUnderlying;
    uint256 _nonce;
    address public oracleSigner;

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

    event ChangeCollateralAllowed(ILendingStrategy.SetAllowedCollateralArg arg);

    constructor(string memory name, string memory symbol, uint256 targetAPR, uint256 maxLTV, uint256 indexMarkRatioMax, uint256 indexMarkRatioMin, ERC20 underlying)
        LinearPerpetual(underlying, new DebtToken(name, symbol, underlying.symbol()), targetAPR, maxLTV, indexMarkRatioMax, indexMarkRatioMin)
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

        uint256 vaultId = vaultIdentifier(request.vaultNonce, from);

        _addCollateralToVault(vaultId, request.vaultNonce, collateral, request.oracleInfo);

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
        ILendingStrategy.OracleInfo calldata oracleInfo
    ) public {
        uint256 vaultId = vaultIdentifier(vaultNonce, msg.sender);
        _addCollateralToVault(vaultId, vaultNonce, collateral, oracleInfo);
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
        bytes calldata data
    ) public {
        uint256 vaultId = vaultIdentifier(vaultNonce, vaultOwner);
        _addCollateralToVault(vaultId, vaultNonce, collateral, oracleInfo);
        IPostCollateralCallback(msg.sender).postCollateralCallback(
            ILendingStrategy.StrategyDefinition(targetAPR, maxLTV, underlying), collateral, data
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
        DebtToken(address(perpetual)).burn(msg.sender, amount);
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

    function setOracleSigner(address signer) public onlyOwner {
        oracleSigner = signer;
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
        DebtToken(address(perpetual)).mint(mintTo, amount);

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
        ILendingStrategy.OracleInfo memory oracleInfo
    ) internal {
        bytes32 h = collateralHash(collateral, vaultId);
        (, uint256 oraclePrice) = abi.decode(oracleInfo.message.payload, (address, uint256));

        if (collateralFrozenOraclePrice[h] != 0) {
            // collateral is already here
            revert();
        }

        if (oraclePrice == 0) {
            revert();
        }

        if (!isAllowed[address(collateral.addr)]) {
            revert ILendingStrategy.InvalidCollateral();
        }

        if (!_verifyOracleSignature(oracleInfo)) {
            revert ILendingStrategy.IncorrectOracleSigner();
        }

        if (!_verifyOracleMessageForCorrectNFT(oracleInfo.message, address(collateral.addr))) {
            revert ILendingStrategy.InvalidOracleMessage();
        }

        collateralFrozenOraclePrice[h] = oraclePrice;
        vaultInfo[vaultId].collateralValue += uint128(oraclePrice);

        emit AddCollateral(vaultId, vaultNonce, collateral, oracleInfo);
    }

    function _verifyOracleSignature(ILendingStrategy.OracleInfo memory oracleInfo) internal returns (bool) {
        address signerAddress = ecrecover(
            keccak256(
                abi.encodePacked(
                    "\x19Ethereum Signed Message:\n32",
                    // EIP-712 structured-data hash
                    keccak256(
                        abi.encode(
                            keccak256(
                                "Message(bytes32 id,bytes payload,uint256 timestamp)"
                            ),
                            oracleInfo.message.id,
                            oracleInfo.message.payload,
                            oracleInfo.message.timestamp
                        )
                    )
                )
            ),
            oracleInfo.sig.v,
            oracleInfo.sig.r,
            oracleInfo.sig.s
        );

        // Ensure the signer matches the designated oracle address
        return signerAddress == oracleSigner;
    }

    function _verifyOracleMessageForCorrectNFT(ILendingStrategy.OracleMessage memory message, address collateral) internal returns (bool) {
        bytes32 expectedId = keccak256(
            abi.encode(
                keccak256(
                    "ContractWideCollectionPrice(uint8 kind,uint256 twapMinutes,address contract)"
                ),
                1,
                30 days / 60, // minutes in a month
                collateral
            )
        );

        return message.id == expectedId;
    }
}
