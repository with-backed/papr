pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

contract PVPStaker {
    ERC20 token;

    struct Stake {
        uint256 amount;
        uint256 depositedAt;
    }

    mapping(address => Stake) public balance;

    uint256 public constant WAD = 1e6;
    uint256 public DAYS_PER_YEAR = 365;
    uint256 public GROWTH_PER_DAY = (10e6 / DAYS_PER_YEAR);

    error AlreadyStaking();
    error StakeTooShort();

    constructor(ERC20 _token) {
        token = _token;
        token.approve(address(this), 2**256 - 1);
    }

    function stake(uint256 amount) public {
        if (balance[msg.sender].amount != 0) {
            revert AlreadyStaking();
        }
        Stake memory stake = Stake({
            amount: amount,
            depositedAt: block.timestamp
        });
        balance[msg.sender] = stake;
        token.transferFrom(msg.sender, address(this), amount);
    }

    function unstake() public returns (uint256) {
        Stake memory stake = balance[msg.sender];
        balance[msg.sender] = Stake({amount: 0, depositedAt: 0});
        uint256 numberOfDays = (block.timestamp - stake.depositedAt) / 1 days;
        if (numberOfDays < 1) {
            revert StakeTooShort();
        }

        uint256 rewards = (stake.amount * (GROWTH_PER_DAY * numberOfDays)) /
            WAD;
        uint256 total = stake.amount + rewards;
        (bool success, ) = address(token).call(
            abi.encodeWithSignature(
                "mint(address,uint256)",
                address(this),
                rewards
            )
        );

        token.transferFrom(address(this), msg.sender, total);
        return total;
    }
}
