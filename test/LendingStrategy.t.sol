// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";
import {TickMath} from "fullrange/libraries/TickMath.sol";

import {Oracle} from "src/squeeth/Oracle.sol";
import {LendingStrategy} from "src/LendingStrategy.sol";

contract TestERC721 is ERC721("TEST", "TEST") {
    function mint(address to, uint256 id) external {
        _mint(to, id);
    }

    function tokenURI(uint256 id) public view override returns (string memory) {

    }
}

interface INonfungiblePositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    /// @notice Creates a new position wrapped in a NFT
    /// @dev Call this when the pool does exist and is initialized. Note that if the pool is created but not initialized
    /// a method does not exist, i.e. the pool is assumed to be initialized.
    /// @param params The params necessary to mint a position, encoded as `MintParams` in calldata
    /// @return tokenId The ID of the token that represents the minted position
    /// @return liquidity The amount of liquidity for this position
    /// @return amount0 The amount of token0
    /// @return amount1 The amount of token1
    function mint(MintParams calldata params)
        external
        payable
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );
}


contract LendingStrategyTest is Test {
    TestERC721 nft = new TestERC721();
    WETH weth = WETH(payable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));
    Oracle oracle = new Oracle();
    LendingStrategy strategy;
    INonfungiblePositionManager positionManager = INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    address borrower = address(1);
    address lender = address(2);

    function setUp() public {
        vm.warp(1);
        strategy = new LendingStrategy("PUNKs Loans", "PL", weth, oracle);
        nft.mint(borrower, 1);
        vm.prank(borrower);
        nft.approve(address(strategy), 1);

        address tokenA = address(strategy.debtSynth());
        address tokenB = address(weth);
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        uint256 token0Amount;
        uint256 token1Amount;

        if (token0 == tokenB) {
            token0Amount = 1e18;
        } else {
            token1Amount = 1e18;
        }

        vm.startPrank(lender);
        weth.approve(address(positionManager), 1e18);
        vm.deal(lender, 1e30);
        weth.deposit{value: 1e30}();
        // weth.approve(address(strategy.pool()), 1e18);

        vm.warp(10);

        uint160 oneToOnePrice = uint160(((10 ** ERC20(token1).decimals()) << 96) / (10 ** ERC20(token0).decimals()) / 2);

        INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager.MintParams(
            strategy.pool().token0(),
            strategy.pool().token1(),
            10000,
            0,
            200,
            token0Amount,
            token1Amount,
            0, 
            0,
            lender,
            block.timestamp + 1
        );

        strategy.pool().initialize(TickMath.getSqrtRatioAtTick(0));
        positionManager.mint(mintParams);
    }

    function testExample() public {
        vm.warp(1 weeks);
        uint256 p = oracle.getTwap(
            address(strategy.pool()), address(strategy.debtSynth()), address(weth), uint32(1), false
        );
        // emit log_named_uint('contract thinks each debt token should be worth', strategy.index());
        // emit log_named_uint('but debt token is actually worth', strategy.mark(1));
        // emit log_named_uint('so contract multiplies normal interest by', strategy.targetMultiplier());
        // emit log_named_uint('and so, for the contract, each debt token is now worth', strategy.newNorm());

        emit log_string(
            string.concat(
                'contract thinks each debt token should be worth ', 
                UintStrings.decimalString(strategy.index(), 18, false),
                ' ',
                weth.symbol()
            )
        );
        emit log_string(
            string.concat(
                'but (according to uniswap) debt token is actually worth ', 
                UintStrings.decimalString(strategy.mark(1), 18, false),
                ' ',
                weth.symbol()
            )
        );
        emit log_string(
            string.concat(
                'so contract multiplies normal interest by ', 
                UintStrings.decimalString(strategy.targetMultiplier(), 18, false)
            )
        );
        emit log_string(
            string.concat(
                'and so, for the contract, each debt token is now worth ', 
                UintStrings.decimalString(strategy.newNorm(), 18, false),
                ' ',
                weth.symbol()
            )
        );
    }
}

library UintStrings {
    /** 
     * @notice Converts `number` into a decimal string, with '%' is `isPercent` = true
     * @param number The number to convert to a string
     * @param decimals The number of decimals `number` should have when converted to a string
     * for example, number = 15 and decimals = 0 would yield "15", 
     * whereas number = 15 and decimals = 1 would yield "1.5"
     * @param isPercent Whether the string returned should include '%' at the end
     * @return string
     */
    function decimalString(uint256 number, uint8 decimals, bool isPercent) internal pure returns (string memory) {
        if (number == 0) return isPercent ? "0%" : "0";
        
        uint8 percentBufferOffset = isPercent ? 1 : 0;
        uint256 tenPowDecimals = 10 ** decimals;

        uint256 temp = number;
        uint8 digits;
        uint8 numSigfigs;
        while (temp != 0) {
            if (numSigfigs > 0) {
                // count all digits preceding least significant figure
                numSigfigs++;
            } else if (temp % 10 != 0) {
                numSigfigs++;
            }
            digits++;
            temp /= 10;
        }

        DecimalStringParams memory params;
        params.isPercent = isPercent;
        if ((digits - numSigfigs) >= decimals) {
            // no decimals, ensure we preserve all trailing zeros
            params.sigfigs = number / tenPowDecimals;
            params.sigfigIndex = digits - decimals;
            params.bufferLength = params.sigfigIndex + percentBufferOffset;
        } else {
            // chop all trailing zeros for numbers with decimals
            params.sigfigs = number / (10 ** (digits - numSigfigs));
            if (tenPowDecimals > number) {
                // number is less than one
                // in this case, there may be leading zeros after the decimal place 
                // that need to be added

                // offset leading zeros by two to account for leading '0.'
                params.zerosStartIndex = 2;
                params.zerosEndIndex = decimals - digits + 2;
                params.sigfigIndex = numSigfigs + params.zerosEndIndex;
                params.bufferLength = params.sigfigIndex + percentBufferOffset;
                params.isLessThanOne = true;
            } else {
                // In this case, there are digits before and
                // after the decimal place
                params.sigfigIndex = numSigfigs + 1;
                params.decimalIndex = digits - decimals + 1;
            }
        }
        params.bufferLength = params.sigfigIndex + percentBufferOffset;
        return generateDecimalString(params);
    }

    /// @dev the below is from
    /// https://github.com/Uniswap/uniswap-v3-periphery/blob/main/contracts/libraries/NFTDescriptor.sol#L189-L231
    // with modifications

    struct DecimalStringParams {
        // significant figures of decimal
        uint256 sigfigs;
        // length of decimal string
        uint8 bufferLength;
        // ending index for significant figures (funtion works backwards when copying sigfigs)
        uint8 sigfigIndex;
        // index of decimal place (0 if no decimal)
        uint8 decimalIndex;
        // start index for trailing/leading 0's for very small/large numbers
        uint8 zerosStartIndex;
        // end index for trailing/leading 0's for very small/large numbers
        uint8 zerosEndIndex;
        // true if decimal number is less than one
        bool isLessThanOne;
        // true if string should include "%"
        bool isPercent;
    }

    function generateDecimalString(DecimalStringParams memory params) private pure returns (string memory) {
        bytes memory buffer = new bytes(params.bufferLength);
        if (params.isPercent) {
            buffer[buffer.length - 1] = '%';
        }
        if (params.isLessThanOne) {
            buffer[0] = '0';
            buffer[1] = '.';
        }

        // add leading/trailing 0's
        for (uint256 zerosCursor = params.zerosStartIndex; zerosCursor < params.zerosEndIndex; zerosCursor++) {
            buffer[zerosCursor] = bytes1(uint8(48));
        }
        // add sigfigs
        while (params.sigfigs > 0) {
            if (params.decimalIndex > 0 && params.sigfigIndex == params.decimalIndex) {
                buffer[--params.sigfigIndex] = '.';
            }
            buffer[--params.sigfigIndex] = bytes1(uint8(uint256(48) + (params.sigfigs % 10)));
            params.sigfigs /= 10;
        }
        return string(buffer);
    }
}
