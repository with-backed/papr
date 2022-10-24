pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {BoringOwnable} from "@boringsolidity/BoringOwnable.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeCast} from "v3-core/contracts/libraries/SafeCast.sol";

contract PVPUSDC is
    ERC20("Backed PVP USDC", "PVPUSDC", 6),
    BoringOwnable,
    Test
{
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

    function stake(uint256 amount) public {
        if (balance[msg.sender].amount != 0) {
            revert AlreadyStaking();
        }
        Stake memory stake = Stake({
            amount: amount,
            depositedAt: block.timestamp
        });
        balance[msg.sender] = stake;
        _burn(msg.sender, amount);
    }

    function unstake() public returns (uint256) {
        Stake memory stake = balance[msg.sender];
        delete balance[msg.sender];

        uint256 secondsElapsed = block.timestamp - stake.depositedAt;
        uint256 ratio = FixedPointMathLib.divWadDown(
            secondsElapsed,
            SECONDS_PER_YEAR
        );

        uint256 total = (stake.amount *
            uint256(
                FixedPointMathLib.powWad(APR.toInt256(), ratio.toInt256())
            )) / FixedPointMathLib.WAD;
        _mint(msg.sender, total);

        return total;
    }
}
