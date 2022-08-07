// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";

import {DebtSynth} from "./DebtSynth.sol";

struct Collateral {
    address addr;
    uint256 amountOrId;
}

struct Loan {
    uint256 nonce;
    Collateral collateral;
    // the oracle price is frozen when loan is created
    // there is no oracle based liquidations
    uint256 oraclePrice;
}

enum OracleInfoPeriod { SevenDays, ThirtyDays, NinetyDays }

struct OracleInfo {
    uint256 price;
    OracleInfoPeriod period;
}

struct Sig {
    uint8 v;
    bytes32 r;
    bytes32 s;
}

contract LendingStrategy {
    uint256 constant ONE = 1e18;
    uint256 constant maxLTV = ONE * 5 / 100;
    uint256 constant perBlockFeeGrowth = ONE / 1e7; // 0.00001%
    uint128 normalization = 1e18;
    uint128 lastUpdated = uint128(block.number);
    DebtSynth debtSynth;
    ERC20 underlying;
    address pool;
    mapping(bytes32 => uint256) public loanDebt;

    constructor(string memory name, string memory symbol) {
        debtSynth = new DebtSynth(name, symbol);
        PoolAddress = 
    }

    function borrow(uint256 debt, Loan calldata loan, OracleInfo calldata oracleInfo, Sig calldata sig) external {
        updateNormalization();

        bytes32 k = loanKey(loan);

        if (loanDebt[k] != 0) {
            revert('exists');
        }

        if (debt == 0) {
            revert('zero');
        }

        

        if (debt > maxDebt(oracleInfo.price)) {
            revert('too much debt');
        }

        if (loan.oraclePrice != oracleInfo.price) {
            revert('mismatch');
        }

        /// check hash(oracleInfo) matches sig recovery
        /// post collateral

        loanDebt[k] = debt;
        debtSynth.mint(msg.sender, debt);
    }

    function payDebt(bytes32 loanKey, uint256 amount) external {
        loanDebt[loanKey] -= amount;
        debtSynth.burn(msg.sender, amount);
    }

    function liquidate(Loan calldata loan) external {
        updateNormalization();

        if (normalization < liquidationPrice(loan) * ONE) {
            revert('not liquidatable');
        }
    }

    function updateNormalization() public returns (uint256) {
        lastUpdated = uint128(block.number);
        normalization = uint128(newNorm());
    }

    function newNorm() public view returns (uint256 newNorm) {
        uint256 passed = block.number - uint256(lastUpdated);

        if (passed == 0) return normalization;

        uint256 cur = normalization;
        uint256 newNorm = cur + (normalization * passed * perBlockFeeGrowth);
    }

    function synthPriceInUnderlying() external view returns (uint256) {
        return normalization / ONE;
    }

    // returns price in terms of underlying:debtSynth
    // i.e. when debt synth reaches this price in underlying terms
    // the loan will be liquidatable 
    function liquidationPrice(Loan calldata loan) public view returns (uint256) {
        bytes32 k = loanKey(loan);

        uint256 maxLoanUnderlying = loan.oraclePrice * maxLTV / ONE;
        return maxLoanUnderlying / loanDebt[k];
    }

    /// @notice given a supposed asset price (would have to be passed on oracle message to be realized)
    /// returns how much synthDebt could be minted
    function maxDebt(uint256 price) public returns (uint256) {
        uint256 maxLoanUnderlying = price * maxLTV / ONE;
        return maxLoanUnderlying / normalization;
    }

    function loanKey(Loan calldata loan) public pure returns (bytes32) {
        keccak256(abi.encode(loan));
    }

    function _oraclePeriod(uint32 _period) internal view returns (uint32) {
        uint32 maxPeriodPool1 = IOracle(oracle).getMaxPeriod(ethQuoteCurrencyPool);

        uint32 maxSafePeriod = maxPeriodPool1 > maxPeriodPool2 ? maxPeriodPool2 : maxPeriodPool1;
        return _period > maxSafePeriod ? maxSafePeriod : _period;
    }
}
