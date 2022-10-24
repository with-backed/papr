pragma solidity ^0.8.13;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {BoringOwnable} from "@boringsolidity/BoringOwnable.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeCast} from "v3-core/contracts/libraries/SafeCast.sol";

contract PHUSDC is ERC20("PAPR Heroes USDC", "phUSDC"), BoringOwnable {
    using SafeCast for uint256;

    error StakingTooMuch();

    struct Stake {
        uint256 amount;
        uint256 depositedAt;
    }

    mapping(address => Stake) public stakeInfo;

    uint256 public constant SECONDS_PER_YEAR = 365 days;
    uint256 public APR = 1.1e18;

    constructor() {
        transferOwnership(msg.sender, false, false);
    }

    function decimals() public view override returns (uint8) {
        return 6;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return super.balanceOf(account) - stakeInfo[account].amount;
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
    }

    function stake(uint256 amountToStake) public {
        if (amountToStake > balanceOf(msg.sender)) {
            revert StakingTooMuch();
        }

        Stake storage currentStake = stakeInfo[msg.sender];
        uint256 newAmount = amountToStake;
        if (currentStake.amount != 0) {
            newAmount += stakedBalance(currentStake);
        }
        currentStake.amount = newAmount;
        currentStake.depositedAt = block.timestamp;
    }

    function unstake() public returns (uint256 total) {
        Stake memory stake = stakeInfo[msg.sender];
        delete stakeInfo[msg.sender];

        uint256 secondsElapsed = block.timestamp - stake.depositedAt;
        uint256 ratio = FixedPointMathLib.divWadDown(secondsElapsed, SECONDS_PER_YEAR);

        total = stakedBalance(stake);
        _mint(msg.sender, total - stake.amount);
    }

    function stakedBalance(Stake memory stake) public view returns (uint256 newBalance) {
        uint256 secondsElapsed = block.timestamp - stake.depositedAt;
        uint256 ratio = FixedPointMathLib.divWadDown(secondsElapsed, SECONDS_PER_YEAR);

        newBalance =
            (stake.amount * uint256(FixedPointMathLib.powWad(APR.toInt256(), ratio.toInt256()))) / FixedPointMathLib.WAD;
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        if (amount > balanceOf(from) && from != address(0)) {
            revert("ERC20: transfer amount exceeds balance");
        }
    }
}
