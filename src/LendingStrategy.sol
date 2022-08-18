// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC721, ERC721TokenReceiver} from "solmate/tokens/ERC721.sol";
import {IUniswapV3Factory} from
    "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from
    "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {TickMath} from "fullrange/libraries/TickMath.sol";

import {DebtToken} from "./DebtToken.sol";
import {DebtVault} from "./DebtVault.sol";
import {IOracle} from "src/squeeth/IOracle.sol";
import {FixedPointMathLib} from "src/libraries/FixedPointMathLib.sol";

struct Collateral {
    ERC721 nft;
    uint256 id;
}

struct VaultInfo {
    uint128 debt;
    uint128 price;
}

enum OracleInfoPeriod {
    SevenDays,
    ThirtyDays,
    NinetyDays
}

struct OracleInfo {
    uint128 price;
    OracleInfoPeriod period;
}

struct Sig {
    uint8 v;
    bytes32 r;
    bytes32 s;
}

struct OpenVaultRequest {
    address mintTo;
    uint128 debt;
    Collateral collateral;
    OracleInfo oracleInfo;
    Sig sig;
}

contract LendingStrategy is ERC721TokenReceiver {
    uint256 immutable start;
    uint256 constant ONE = 1e18;
    uint24 constant UNISWAP_FEE_TIER = 10000;
    uint256 public constant maxLTV = ONE * 5 / 10; // 50%
    uint256 constant PERIOD = 4 weeks;
    uint256 public targetGrowthPerPeriod = 20 * ONE / 52 / 4; // 20% APR
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
    mapping(bytes32 => VaultInfo) public vaultInfo;

    modifier onlyVaultOwner(bytes32 vaultKey) {
        if (msg.sender != debtVault.ownerOf(uint256(vaultKey))) {
            revert('only owner');
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
        pool =
            IUniswapV3Pool(factory.createPool(address(underlying), address(debtToken), UNISWAP_FEE_TIER));
        pool.initialize(TickMath.getSqrtRatioAtTick(0));
        oracle = _oracle;
        start = block.timestamp;
        lastUpdated = uint128(block.timestamp);
        name = _name;
        symbol = _symbol;
    }

    function openVault(
        OpenVaultRequest memory request
    )
        public
    {
        updateNormalization();

        bytes32 k = vaultKey(request.collateral);

        // can probably make opening vault and minting debt two seperate
        // funcs and use a multicall
        if (request.debt == 0 || request.oracleInfo.price == 0) {
            revert("zero");
        }

        if (request.debt > maxDebt(request.oracleInfo.price)) {
            revert("too much debt");
        }

        vaultInfo[k].debt = request.debt;
        vaultInfo[k].price = request.oracleInfo.price;
        
        debtToken.mint(request.mintTo, request.debt);
        debtVault.mint(request.mintTo, uint256(k));

        if (request.collateral.nft.ownerOf(request.collateral.id) != address(this)) {
            revert('not owner');
        }
    }

    function onERC721Received(
        address,
        address,
        uint256 _id,
        bytes calldata data
    ) external override returns (bytes4) {
        OpenVaultRequest memory request = abi.decode(data, (OpenVaultRequest));

        openVault(request);

        return ERC721TokenReceiver.onERC721Received.selector;
    }

    function increaseDebt(bytes32 vaultKey, uint128 amount) external onlyVaultOwner(vaultKey) {
        vaultInfo[vaultKey].debt += amount;
        debtToken.mint(msg.sender, amount);

        if (vaultInfo[vaultKey].debt > maxDebt(vaultInfo[vaultKey].price)) {
            revert('too much debt');
        }
    }

    function reduceDebt(bytes32 vaultKey, uint128 amount) external {
        vaultInfo[vaultKey].debt -= amount;
        debtToken.burn(msg.sender, amount);
    }

    function closeVault(Collateral calldata collateral) external {
        bytes32 key = vaultKey(collateral);

        if (msg.sender != debtVault.ownerOf(uint256(key))) {
            revert('only owner');
        }

        if (vaultInfo[key].debt != 0) {
            revert('still has debt');
        }

        debtVault.burn(uint256(key));
        delete vaultInfo[key];

        collateral.nft.transferFrom(address(this), msg.sender, collateral.id);
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
        normalization = uint128(newNorm());
        lastUpdated = uint128(block.timestamp);
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
        * targetGrowthPerPeriod
        / FixedPointMathLib.WAD
        + FixedPointMathLib.WAD;
    }

    // price of debt token, quoted in underlying units
    // i.e. greater than (1 ** underlying.decimals()) when 1 mark is worth more than 1 underlying
    function mark(uint32 period) public view returns (uint256) {
        // period stuff is kinda weird? Don't we just always want the longest period?
        uint32 periodForOracle = _getConsistentPeriodForOracle(period);
        return oracle.getTwap(
            address(pool), address(debtToken), address(underlying), periodForOracle, false
        );
    }

    /// aka norm growth if updated right now, 
    /// e.g. a result of 12e17 = 1.2 = 20% growth since lastUpdate
    function multiplier() public view returns (int256) {
        // TODO: do we need signed ints? when does powWAD return a negative? 
        uint256 period = block.timestamp - lastUpdated;
        uint256 periodRatio = FixedPointMathLib.divWadDown(period, PERIOD);
        uint256 targetGrowth = FixedPointMathLib.mulWadDown(targetGrowthPerPeriod, periodRatio) + FixedPointMathLib.WAD;
        uint256 indexMarkRatio = FixedPointMathLib.divWadDown(index(), mark(uint32(period)));
        // cap at 140%, floor at 80%
        if (indexMarkRatio > 14e17) {
            indexMarkRatio = 14e17;
        } else if (indexMarkRatio < 8e17) {
            indexMarkRatio = 8e17;
        }
        /// accelerate or deccelerate apprecation based in index/mark. If mark is too high, slow down. If mark is too low, speed up.
        int256 deviationMultiplier = FixedPointMathLib.powWad(int256(indexMarkRatio), int256(periodRatio));

        return deviationMultiplier * int256(targetGrowth) / int256(FixedPointMathLib.WAD);
    }

    // returns price in terms of underlying:debt token
    // i.e. when debt token reaches this price in underlying terms
    // the loan will be liquidatable
    function liquidationPrice(bytes32 key)
        public
        view
        returns (uint256)
    {

        uint256 maxLoanUnderlying = vaultInfo[key].price * maxLTV / ONE;
        return maxLoanUnderlying / vaultInfo[key].debt;
    }

    /// @notice given a supposed asset price (would have to be passed on oracle message to be realized)
    /// returns how much synthDebt could be minted
    function maxDebt(uint256 price) public view returns (uint256) {
        uint256 maxLoanUnderlying = price * maxLTV;
        return maxLoanUnderlying / normalization;
    }

    function vaultKey(Collateral memory collateral) public pure returns (bytes32) {
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