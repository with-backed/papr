// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";
import {IUniswapV3Factory} from
    "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from
    "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {DebtToken} from "./DebtToken.sol";
import {DebtVault} from "./DebtVault.sol";
import {IOracle} from "src/squeeth/IOracle.sol";

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

contract LendingStrategy {
    uint256 immutable start;
    uint256 constant ONE = 1e18;
    uint256 constant maxLTV = ONE * 5 / 10; // 50%
    uint256 constant PERIOD = 1 weeks;
    uint256 public targetGrowthPerPeriod = ONE / 1000; // .1%
    uint128 public normalization = 1e18;
    uint128 public lastUpdated = uint128(block.timestamp);
    DebtToken public debtToken;
    DebtVault public debtVault;
    ERC20 public underlying;
    ERC721 public collateral;
    IOracle oracle;
    IUniswapV3Pool public pool;
    mapping(bytes32 => VaultInfo) public vaultInfo;

    constructor(
        string memory name,
        string memory symbol,
        ERC20 _underlying,
        IOracle _oracle
    ) {
        underlying = _underlying;
        IUniswapV3Factory factory =
            IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
        debtToken = new DebtToken(name, symbol);
        debtVault = new DebtVault(name, symbol);
        pool =
            IUniswapV3Pool(factory.createPool(address(underlying), address(debtToken), 10000));
        oracle = _oracle;
        start = block.timestamp;
        lastUpdated = uint128(block.timestamp);
    }

    function openVault(
        address mintTo,
        uint128 debt,
        Collateral calldata collateral,
        OracleInfo calldata oracleInfo,
        Sig calldata sig
    )
        external
    {
        updateNormalization();

        bytes32 k = vaultKey(collateral);

        if (vaultInfo[k].price != 0) {
            revert("exists");
        }

        if (debt == 0 || oracleInfo.price == 0) {
            revert("zero");
        }

        if (debt > maxDebt(oracleInfo.price)) {
            revert("too much debt");
        }

        vaultInfo[k].debt = debt;
        vaultInfo[k].price = oracleInfo.price;
        
        debtToken.mint(mintTo, debt);
        debtVault.mint(mintTo, uint256(k));

        if (collateral.nft.ownerOf(collateral.id) != address(this)) {
            revert('not owner');
        }
    }

    function increaseDebt(bytes32 vaultKey, uint128 amount) external {
        if (msg.sender != debtVault.ownerOf(uint256(vaultKey))) {
            revert('only owner');
        }


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

    function liquidate(bytes32 vaultKey) external {
        updateNormalization();

        if (normalization < liquidationPrice(vaultKey) * ONE) {
            revert("not liquidatable");
        }
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
        // exchange rate: <uints of debt token> * exchangeRate = units of underlying
        uint256 previousExchangeRate = normalization;
        uint32 period = uint32(block.timestamp - lastUpdated);
        uint256 targetGrowth = targetGrowthPerPeriod * period / PERIOD;

        return previousExchangeRate 
        * (((ONE + targetGrowth) *  targetMultiplier()) / ONE) // TODO I think we might want targetMultiplier to be period adjusted? e.g. don't multiply by a lot if it's only been a few seconds?
        / ONE;
    }

    // what each Debt Token is worth in underlying
    function index() public view returns (uint256) {
        // should we only be looking at the most recent period? 
        return ((block.timestamp - start) * ONE / PERIOD) * targetGrowthPerPeriod / ONE + ONE;
    }

    // price of debt token, quoted in underlying units
    // i.e. greater than (1 ** underlying.decimals()) when 1 mark is worth more than 1 underlying
    function mark(uint32 period) public view returns (uint256){
        // period stuff is kinda weird? Don't we just always want the longest period?
        uint32 periodForOracle = _getConsistentPeriodForOracle(period);
        return oracle.getTwap(
            address(pool), address(debtToken), address(underlying), periodForOracle, false
        );
    }

    // ratio of index to mark, if > 1e18 means mark is too low
    // if < 1e18 means mark is too high
    function targetMultiplier() public view returns (uint256 indexMarkRatio) {
        /// TODO: mark 1 is a temp fix, do we always want that?
        indexMarkRatio = index() * ONE / mark(1);
        if (indexMarkRatio > 5e18) {
            // cap growth at 5x target
            indexMarkRatio = 5e18;
        } else if (indexMarkRatio < 2e17) {
            // floor growth at 1/5 target
            indexMarkRatio = 2e17;
        }
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
    function maxDebt(uint256 price) public returns (uint256) {
        uint256 maxLoanUnderlying = price * maxLTV;
        return maxLoanUnderlying / normalization;
    }

    function vaultKey(Collateral calldata collateral) public pure returns (bytes32) {
        keccak256(abi.encode(collateral));
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