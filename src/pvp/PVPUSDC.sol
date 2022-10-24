pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {BoringOwnable} from "@boringsolidity/BoringOwnable.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeCast} from "v3-core/contracts/libraries/SafeCast.sol";

contract PVPUSDC is ERC20("Backed PVP USDC", "PVPUSDC", 6), BoringOwnable {
    using SafeCast for uint256;

    struct Stake {
        uint256 amount;
        uint256 depositedAt;
    }

    mapping(address => Stake) public balance;

    error AlreadyStaking();

    uint256 public constant SECONDS_PER_YEAR = 365 days;
    uint256 public APR = 1.1e18;

    constructor() {
        transferOwnership(msg.sender, false, false);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function stake(uint256 amountToStake) public {
        Stake memory currentStake = balance[msg.sender];
        uint256 newAmount = amountToStake;
        if (currentStake.amount != 0) {
            newAmount = _calculateNewBalanceFromStake(currentStake);
        }
        Stake memory newStake = Stake({
            amount: newAmount,
            depositedAt: block.timestamp
        });
        balance[msg.sender] = newStake;
        _burn(msg.sender, amountToStake);
    }

    function unstake() public returns (uint256 total) {
        Stake memory stake = balance[msg.sender];
        delete balance[msg.sender];

        uint256 secondsElapsed = block.timestamp - stake.depositedAt;
        uint256 ratio = FixedPointMathLib.divWadDown(
            secondsElapsed,
            SECONDS_PER_YEAR
        );

        total = _calculateNewBalanceFromStake(stake);
        _mint(msg.sender, total);
    }

    function _calculateNewBalanceFromStake(Stake memory stake)
        public
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
