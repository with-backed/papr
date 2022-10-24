pragma solidity ^0.8.13;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {BoringOwnable} from "@boringsolidity/BoringOwnable.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeCast} from "v3-core/contracts/libraries/SafeCast.sol";

contract PVPUSDC is ERC20("Backed PVP USDC", "pUSDC"), BoringOwnable {
    using SafeCast for uint256;

    struct Stake {
        uint256 amount;
        uint256 depositedAt;
    }

    mapping(address => Stake) public stakedBalance;

    error StakingTooMuch();

    uint256 public constant SECONDS_PER_YEAR = 365 days;
    uint256 public APR = 1.1e18;

    constructor() {
        transferOwnership(msg.sender, false, false);
    }

    function decimals() public view override returns (uint8) {
        return 6;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return super.balanceOf(account) - stakedBalance[account].amount;
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function stake(uint256 amountToStake) public {
        if (amountToStake > balanceOf(msg.sender)) {
            revert StakingTooMuch();
        }

        Stake memory currentStake = stakedBalance[msg.sender];
        uint256 newAmount = amountToStake;
        if (currentStake.amount != 0) {
            newAmount =
                _calculateNewBalanceFromStake(currentStake) +
                amountToStake;
        }
        Stake memory newStake = Stake({
            amount: newAmount,
            depositedAt: block.timestamp
        });
        stakedBalance[msg.sender] = newStake;
    }

    function unstake() public returns (uint256 total) {
        Stake memory stake = stakedBalance[msg.sender];
        delete stakedBalance[msg.sender];

        uint256 secondsElapsed = block.timestamp - stake.depositedAt;
        uint256 ratio = FixedPointMathLib.divWadDown(
            secondsElapsed,
            SECONDS_PER_YEAR
        );

        total = _calculateNewBalanceFromStake(stake);
        _mint(msg.sender, total - stake.amount);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        if (amount > balanceOf(from) && from != address(0)) {
            revert("ERC20: transfer amount exceeds balance");
        }
    }

    function _calculateNewBalanceFromStake(Stake memory stake)
        public
        view
        returns (uint256 newBalance)
    {
        uint256 secondsElapsed = block.timestamp - stake.depositedAt;
        uint256 ratio = FixedPointMathLib.divWadDown(
            secondsElapsed,
            SECONDS_PER_YEAR
        );

        newBalance =
            (stake.amount *
                uint256(
                    FixedPointMathLib.powWad(APR.toInt256(), ratio.toInt256())
                )) /
            FixedPointMathLib.WAD;
    }
}
