// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC721, ERC721TokenReceiver} from "solmate/tokens/ERC721.sol";
import {IUniswapV3Factory} from
    "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {TickMath} from "fullrange/libraries/TickMath.sol";

import {DebtToken} from "./DebtToken.sol";
import {DebtVault} from "./DebtVault.sol";
import {Multicall} from "./Multicall.sol";
import {IOracle} from "src/squeeth/IOracle.sol";
import {FixedPointMathLib} from "src/libraries/FixedPointMathLib.sol";
import {IPostCollateralCallback} from "src/interfaces/IPostCollateralCallback.sol";
import {ILendingStrategy} from "src/interfaces/IPostCollateralCallback.sol";

contract LendingStrategy is ERC721TokenReceiver, Multicall {
    uint256 immutable start;
    uint256 constant ONE = 1e18;
    uint24 constant UNISWAP_FEE_TIER = 10000;
    uint256 public constant maxLTV = ONE * 5 / 10; // 50%
    uint256 public constant PERIOD = 4 weeks;
    uint256 public targetGrowthPerPeriod = 20 * ONE / 100 / (52 / 4); // 20% APR
    uint128 public normalization = 1e18;
    uint128 public lastUpdated = uint128(block.timestamp);
    string public name;
    string public symbol;
    DebtToken public debtToken;
    DebtVault public debtVault;
    ERC20 public underlying;
    ERC721 public collateral;
    IOracle oracle;
    IUniswapV3Pool public pool;
    uint256 _nonce;

    // id => vault info
    mapping(uint256 => ILendingStrategy.VaultInfo) public vaultInfo;
    mapping(bytes32 => uint256) public price;

    event VaultCreated(
        uint256 indexed vaultId,
        address indexed mintTo,
        uint256 tokenId,
        uint256 amount
    );
    event DebtAdded(bytes32 indexed vaultKey, uint256 amount);
    event DebtReduced(bytes32 indexed vaultKey, uint256 amount);
    event VaultClosed(bytes32 indexed vaultKey, uint256 tokenId);
    event NormalizationFactorUpdated(uint128 oldNorm, uint128 newNorm);

    modifier onlyVaultOwner(uint256 vaultId) {
        if (msg.sender != debtVault.ownerOf(vaultId)) {
            revert("only owner");
        }
        _;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        ERC721 _collateral,
        ERC20 _underlying,
        IOracle _oracle
    ) {
        underlying = _underlying;
        collateral = _collateral;
        IUniswapV3Factory factory =
            IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
        debtToken = new DebtToken(_name, _symbol, _underlying.symbol());
        debtVault = new DebtVault(_name, _symbol);
        pool = IUniswapV3Pool(
            factory.createPool(address(underlying), address(debtToken), UNISWAP_FEE_TIER)
        );
        pool.initialize(TickMath.getSqrtRatioAtTick(0));
        oracle = _oracle;
        start = block.timestamp;
        lastUpdated = uint128(block.timestamp);
        name = _name;
        symbol = _symbol;
    }

    function openVault(ILendingStrategy.OpenVaultRequest memory request) public returns (uint256 id) {
        updateNormalization();

        id = ++_nonce;
        /// TODO need to think about how best to compose this, 
        /// ideally you could 1. deposit nft, 2. open vault, 3. swap on uniswap
        /// all in one. But that might require a periphery contract. Just annoying because it's more gas  

        // bytes32 k = vaultKey(request.collateral);

        // can probably make opening vault and minting debt two seperate
        // funcs and use a multicall
        // if (request.debt == 0 || request.oracleInfo.price == 0) {
        //     revert("zero");
        // }

        // if (request.debt > maxDebt(request.oracleInfo.price)) {
        //     revert("too much debt");
        // }

        // vaultInfo[id].debt = request.debt;
        // vaultInfo[id].price = request.oracleInfo.price;

        // debtToken.mint(request.mintTo, request.debt);
        debtVault.mint(request.mintTo, id);

        if (
            request.collateral.addr.ownerOf(request.collateral.id) != address(this)
        ) {
            revert("not owner");
        }

        emit VaultCreated(
            id, request.mintTo, request.collateral.id, request.debt
            );
    }

    function addCollateralToVaultWithPull(
        uint256 vaultId,
        ILendingStrategy.Collateral calldata collateral,
        ILendingStrategy.OracleInfo calldata oracleInfo,
        ILendingStrategy.Sig calldata sig
    )
        public
    {
        _addCollateralToVault(vaultId, collateral, oracleInfo, sig);
        collateral.addr.transferFrom(
            msg.sender, address(this), collateral.id
        );
    }

    // allows for sending the NFT to the contract out of band
    function addCollateralWithPossessionCheck(
        uint256 vaultId,
        ILendingStrategy.Collateral calldata collateral,
        ILendingStrategy.OracleInfo calldata oracleInfo,
        ILendingStrategy.Sig calldata sig,
        bytes calldata data
    )
        public
    {
        _addCollateralToVault(vaultId, collateral, oracleInfo, sig);
        if (collateral.addr.ownerOf(collateral.id) != address(this)) {
            revert();
        }
    }

    /// enables borrowers to mint and sell debt in callback
    /// ahead of passing collateral
    /// i.e. loan to buy
    function addCollateralToVaultWithCallback(
        uint256 vaultId,
        ILendingStrategy.Collateral calldata collateral,
        ILendingStrategy.OracleInfo calldata oracleInfo,
        ILendingStrategy.Sig calldata sig,
        bytes calldata data
    )
        public
    {
        _addCollateralToVault(vaultId, collateral, oracleInfo, sig);
        IPostCollateralCallback(msg.sender).postCollateralCallback(collateral, data);
        if (collateral.addr.ownerOf(collateral.id) != address(this)) {
            revert();
        }
    }

    function _addCollateralToVault(
        uint256 vaultId,
        ILendingStrategy.Collateral calldata collateral,
        ILendingStrategy.OracleInfo calldata oracleInfo,
        ILendingStrategy.Sig calldata sig
    )
        internal
    {
        bytes32 h = collateralHash(collateral);
        if (price[h] != 0) {
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
    }

    function onERC721Received(
        address,
        address,
        uint256 _id,
        bytes calldata data
    )
        external
        override
        returns (bytes4)
    {
        ILendingStrategy.OpenVaultRequest memory request = abi.decode(data, (ILendingStrategy.OpenVaultRequest));

        openVault(request);

        return ERC721TokenReceiver.onERC721Received.selector;
    }

    function increaseDebt(uint256 vaultId, uint128 amount)
        external
        onlyVaultOwner(vaultId)
    {
        updateNormalization();

        vaultInfo[vaultId].debt += amount;
        debtToken.mint(msg.sender, amount);

        if (vaultInfo[vaultId].debt > maxDebt(vaultInfo[vaultId].price)) {
            revert("too much debt");
        }

        emit DebtAdded(vaultId, amount);
    }

    function reduceDebt(bytes32 vaultKey, uint128 amount) external {
        vaultInfo[vaultKey].debt -= amount;
        debtToken.burn(msg.sender, amount);
        emit DebtReduced(vaultKey, amount);
    }

    function closeVault(uint256 vaultId) external onlyVaultOwner(vaultId) {
        if (vaultInfo[vaultId].debt != 0) {
            revert("still has debt");
        }

        debtVault.burn(vaultId);
        delete vaultInfo[vaultId];

        // TODO allow batch removing of collateral
        // collateral.addr.transferFrom(address(this), msg.sender, collateral.id);

        emit VaultClosed(vaultId, 1);
    }

    function liquidate(bytes32 vaultKey) external {
        updateNormalization();

        if (normalization < liquidationPrice(vaultKey) * ONE) {
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
        uint128 newNormalization = uint128(newNorm());

        normalization = newNormalization;
        lastUpdated = uint128(block.timestamp);

        emit NormalizationFactorUpdated(previousNormalization, newNormalization);
    }

    function newNorm() public view returns (uint256 newNorm) {
        if (lastUpdated == block.timestamp) {
            return normalization;
        }

        return FixedPointMathLib.mulWadDown(normalization, uint256(multiplier()));
    }

    // what each Debt Token is worth in underlying
    function index() public view returns (uint256) {
        return FixedPointMathLib.divWadDown(block.timestamp - start, PERIOD)
            * targetGrowthPerPeriod / FixedPointMathLib.WAD
            + FixedPointMathLib.WAD;
    }

    // price of debt token, quoted in underlying units
    // i.e. greater than (1 ** underlying.decimals()) when 1 mark is worth more than 1 underlying
    function mark(uint32 period) public view returns (uint256) {
        // period stuff is kinda weird? Don't we just always want the longest period?
        uint32 periodForOracle = _getConsistentPeriodForOracle(period);
        return oracle.getTwap(
            address(pool),
            address(debtToken),
            address(underlying),
            periodForOracle,
            false
        );
    }

    /// aka norm growth if updated right now,
    /// e.g. a result of 12e17 = 1.2 = 20% growth since lastUpdate
    function multiplier() public view returns (int256) {
        // TODO: do we need signed ints? when does powWAD return a negative?
        uint256 period = block.timestamp - lastUpdated;
        uint256 periodRatio = FixedPointMathLib.divWadDown(period, PERIOD);
        uint256 targetGrowth = FixedPointMathLib.mulWadDown(
            targetGrowthPerPeriod, periodRatio
        ) + FixedPointMathLib.WAD;
        uint256 m = mark(uint32(period));
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

    // returns price in terms of underlying:debt token
    // i.e. when debt token reaches this price in underlying terms
    // the loan will be liquidatable
    function liquidationPrice(bytes32 key) public view returns (uint256) {
        uint256 maxLoanUnderlying = vaultInfo[key].price * maxLTV / ONE;
        return maxLoanUnderlying / vaultInfo[key].debt;
    }

    /// @notice given a supposed asset price (would have to be passed on oracle message to be realized)
    /// returns how much synthDebt could be minted
    function maxDebt(uint256 price) public view returns (uint256) {
        uint256 maxLoanUnderlying = price * maxLTV;
        return maxLoanUnderlying / normalization;
    }

    function collateralHash(ILendingStrategy.Collateral memory collateral)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(collateral));
    }

    function _getConsistentPeriodForOracle(uint32 _period)
        internal
        view
        returns (uint32)
    {
        uint32 maxSafePeriod = IOracle(oracle).getMaxPeriod(address(pool));

        return _period > maxSafePeriod ? maxSafePeriod : _period;
    }
}
