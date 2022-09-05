// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.13;

// import "forge-std/Test.sol";

// import {ILendingStrategy} from "src/interfaces/ILendingStrategy.sol";
// import {StrategyFactory} from "src/core/StrategyFactory.sol";
// import {LendingStrategy} from "src/core/LendingStrategy.sol";
// import {TestERC20} from 'test/mocks/TestERC20.sol';
// import {TestERC721} from 'test/mocks/TestERC721.sol';
// import {UniswapV3Factory} from 'test/mocks/UniswapV3Factory.sol';

// contract LendingStrategyTest is Test {
//     LendingStrategy strategy;
//     TestERC20 underlying = new TestERC20();
//     TestERC721 collateral = new TestERC721();
//     ILendingStrategy.OnERC721ReceivedArgs safeTransferReceivedArgs;
//     address borrower = address(1);
//     uint256 collateralId = 1;

//     // args for safe transfer receive data
//     uint256 vaultId;
//     uint256 vaultNonce;
//     uint256 minOut;
//     int256 debt;
//     uint160 sqrtPriceLimitX96;
//     uint128 oraclePrice;
//     ILendingStrategy.OracleInfo oracleInfo;
//     ILendingStrategy.Sig sig;
//     //

//     function setUp() public {
//         UniswapV3Factory f = new UniswapV3Factory();
//         vm.etch(0x1F98431c8aD98523631AE4a59f267346ea31F984, address(f).code);
//         StrategyFactory factory = new StrategyFactory();
//         strategy = factory.newStrategy('name', 'symbol', 'uri', '', 0.2e18, 0.5e18, underlying);

//         oracleInfo.price = oraclePrice;

// safeTransferReceivedArgs = ILendingStrategy.OnERC721ReceivedArgs({
//     vaultId: vaultId,
//     vaultNonce: vaultNonce,
//     mintVaultTo: borrower,
//     mintDebtOrProceedsTo: borrower,
//     minOut: minOut,
//     debt: debt,
//     sqrtPriceLimitX96: sqrtPriceLimitX96,
//     oracleInfo: oracleInfo,
//     sig: sig
// });

//         collateral.mint(borrower, collateralId);
//     }

//     function testSafeTransferAddCollateralToExistingVault() public {
//         vm.startPrank(borrower);
//         uint256 id = strategy.openVault(address(this));
//         safeTransferReceivedArgs.vaultId = id;
//         collateral.safeTransferFrom(
//             borrower,
//             address(strategy),
//             collateralId,
//             abi.encode(safeTransferReceivedArgs)
//         );
//     }

// }
