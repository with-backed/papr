// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";
import {TickMath} from "fullrange/libraries/TickMath.sol";
import {IQuoter} from "v3-periphery/interfaces/IQuoter.sol";
import {ISwapRouter} from 'v3-periphery/interfaces/ISwapRouter.sol';

import {Oracle} from "src/squeeth/Oracle.sol";
import {LendingStrategy, Collateral, VaultInfo, Sig, OracleInfo, OracleInfoPeriod, OpenVaultRequest} from "src/LendingStrategy.sol";
import {StrategyFactory} from "src/StrategyFactory.sol";
import {FixedPointMathLib} from "src/libraries/FixedPointMathLib.sol";

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
    StrategyFactory factory;
    TestERC721 nft = new TestERC721();
    WETH weth = WETH(payable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));
    Oracle oracle = new Oracle();
    LendingStrategy strategy;
    INonfungiblePositionManager positionManager = INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    IQuoter quoter = IQuoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);
    ISwapRouter router = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    address borrower = address(1);
    address lender = address(2);
    uint24 feeTier = 10000;

    event VaultCreated(bytes32 indexed vaultKey, address indexed mintTo, uint256 tokenId, uint256 amount);
    event DebtAdded(bytes32 indexed vaultKey, uint256 amount);
    event DebtReduced(bytes32 indexed vaultKey, uint256 amount);
    event VaultClosed(bytes32 indexed vaultKey, uint256 tokenId);
    event NormalizationFactorUpdated(uint128 oldNorm, uint128 newNorm);

    function setUp() public {
        vm.warp(1);
        factory = new StrategyFactory();
        strategy = factory.newStrategy("PUNKs Loans", "PL", nft, weth);
        nft.mint(borrower, 1);
        vm.prank(borrower);
        nft.approve(address(strategy), 1);

        address tokenA = address(strategy.debtToken());
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

        vm.warp(10);

        INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager.MintParams(
            strategy.pool().token0(),
            strategy.pool().token1(),
            feeTier,
            -200,
            0,
            token0Amount,
            token1Amount,
            0, 
            0,
            lender,
            block.timestamp + 1
        );

        // uint256 q = quoter.quoteExactInputSingle(
        //     address(strategy.debtToken()),
        //     address(strategy.underlying()),
        //     feeTier,
        //     1e18,
        //     0
        // );
        // emit log_named_uint('quote 1 eth', q);

        positionManager.mint(mintParams);
        vm.stopPrank();
    }

    function testBorrow() public {
        vm.warp(block.timestamp + 1);
        vm.startPrank(borrower);
        // nft.transferFrom(borrower, address(strategy), 1);

        OpenVaultRequest memory request = OpenVaultRequest(
            borrower,
            1e18,
            Collateral({
                nft: nft, 
                id: 1
            }),
            OracleInfo({
                price: 3e18,
                period: OracleInfoPeriod.SevenDays
            }),
            Sig({
                v: 1,
                r: keccak256('x'),
                s: keccak256('x')
            })
        );
        strategy.updateNormalization();

        vm.expectEmit(true, true, false, false);
        emit VaultCreated(strategy.vaultKey(request.collateral), borrower, 1, 1e18);
        nft.safeTransferFrom(
            borrower,
            address(strategy),
            1,
            abi.encode(request)
        );

        uint256 q = quoter.quoteExactInputSingle(
            address(strategy.debtToken()),
            address(strategy.underlying()),
            feeTier,
            1e18,
            0
        );
        emit log_named_uint('quote 1 eth', q);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(strategy.debtToken()),
            tokenOut: address(strategy.underlying()),
            fee: feeTier,
            recipient: borrower,
            deadline: block.timestamp + 15,
            amountIn: 1e18,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        strategy.debtToken().approve(address(router), 1e18);

        router.exactInputSingle(params);

        vm.warp(block.timestamp + 1);

        _print();

         q = quoter.quoteExactInputSingle(
            address(strategy.underlying()),
            address(strategy.debtToken()),
            feeTier,
            1e18,
            0
        );
        emit log_string(
            string.concat(
                'quote 1 debt token ',
                UintStrings.decimalString(q, 18, false),
                ' ', 
                strategy.underlying().symbol()
            )
        );
    }

    function testExample() public {
        vm.warp(1 weeks);
        
        uint256 p = oracle.getTwap(
            address(strategy.pool()), address(strategy.debtToken()), address(weth), uint32(1), false
        );
        strategy.newNorm();
        strategy.updateNormalization();
    }

    function _print() internal {
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
                UintStrings.decimalString(uint256(strategy.multiplier()), 18, false)
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

contract TestMath is Test {
    uint256 constant PERIOD = 4 weeks;
    uint256 annualAPR = FixedPointMathLib.WAD * 52 / 100;
    uint256 targetGrowthPerPeriod = annualAPR / (52 weeks / PERIOD); // 1% weekly
    uint256 start;
    uint256 lastUpdate;
    function testMath1() public {
        vm.warp(1 weeks);
        uint256 index = index();
        // uint256 mark = 102e16;
        uint256 mark = 1e18;
        uint256 rFunding = FixedPointMathLib.divWadDown(block.timestamp - start, PERIOD);
        uint256 indexMarkRatio = FixedPointMathLib.divWadDown(index, mark);
        int256 multiplier = FixedPointMathLib.powWad(int256(indexMarkRatio), int256(rFunding));
        if (multiplier > 5 * 1e18) {
            multiplier = 5 * 1e18;
        }
        uint256 targetGrowth = FixedPointMathLib.mulWadDown(targetGrowthPerPeriod, rFunding) + FixedPointMathLib.WAD;
        emit log_named_uint("rFunding", rFunding);
        emit log_string(string.concat("target annual growth ",  UintStrings.decimalString(annualAPR, 16, true)));
        emit log_named_uint("PERIOD in weeks", PERIOD / 1 weeks);
        emit log_named_uint("mark", mark);
        emit log_named_uint("index", index);
        emit log_named_uint("index/mark", indexMarkRatio);

        emit log_named_uint("target growth", targetGrowth);
        emit log_named_int("multiplier", multiplier);
        emit log_named_int('new norm', multiplier * int256(targetGrowth) / int256(FixedPointMathLib.WAD));

        
    }

    function index() public returns (uint256) {
        return FixedPointMathLib.divWadDown(block.timestamp - start, PERIOD) 
        * targetGrowthPerPeriod
        / FixedPointMathLib.WAD
        + FixedPointMathLib.WAD;
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
