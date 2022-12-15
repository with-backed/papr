We *very strongly* encourage everyone to read our [whitepaper](https://backed.mirror.xyz/8SslPvU8of0h-fxoo6AybCpm51f30nd0qxPST8ep08c) to understand more!

## Running code 
`foundryup` + `forge install` + `forge test` will get you up and going. (More info on Foundry [here](https://github.com/foundry-rs/foundry)). Most of the PaprController tests are forking tests: relying on real chain state. To get these working, add an RPC url value (e.g. from Alchemy or Infura) for `MAINNET_RPC_URL` in a `.env` file. 

## Licensing 

Papr is dual-licensed under the Business Source License 1.1 (BUSL-1.1) and MIT as follows:
- PaprController.sol and UniswapOracleFundingRateController.sol may only be licensed under the Business Source License 1.1 (as indicated in their SPDX headers)
- Interfaces, tests,  and other supporting code in ‘src’ may be licensed under either the Business Source License 1.1 or the MIT License (as indicated in their SPDX headers)
- Please note that OracleLibrary.sol, UniswapHelpers.sol, and several test files rely on other open source dependencies which may be subject to other licenses, including:
  - [Uniswap v3-core](https://github.com/Uniswap/v3-core)
  - [Uniswap v3-periphery](https://github.com/Uniswap/v3-periphery)
  - [0xTomyo fullrange](https://github.com/0xTomoyo/fullrange)
  
See [`LICENSE`](https://github.com/with-backed/papr/blob/master/LICENSING.txt).

# How to Try Papr
You can try papr by visiting https://papr.wtf/tokens/paprTrash
This is a Goerli testnet client for the protocol that allows you to lock up fake NFTs as collateral and mint papr tokens. To mint the fake NFTs that the protocol allows as collateral, visit https://papr.wtf/tokens/paprTrash/test

This particular instance of the protocol uses a fake USDC as the underlying token, which you can also mint at the above URL. Finally, you can swap papr tokens for the underlying USDC at the Swap link on the site, as well as provide liquidity for the token pairs at the LP link on the site.