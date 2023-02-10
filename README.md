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

## Disclaimer

The Papr Protocol is a community-driven, decentralized set of blockchain-based smart contracts and tools that enable users mint Papr tokens by depositing NFTs as collateral and transact (using both Tokens and NFTs) via the smart contracts designated by Non-Fungible Ecosystem Foundation. The Protocol does not guarantee any profitability by borrowing or lending any crypto assets as applicable, nor does the Protocol guarantee any value of any crypto assets transferred thereon. Your use of the Protocol is entirely at your own risk.

The Protocol is available on an “as is” basis without warranties of any kind, either express or implied, including, but not limited to, warranties of merchantability, title, fitness for a particular purpose and non-infringement.

You assume all risks associated with using the Protocol, and digital assets and decentralized systems generally, including but not limited to, that: (a) digital assets are highly volatile; (b) using digital assets is inherently risky due to both features of such assets and the potential unauthorized acts of third parties; (c) you may not have ready access to assets; and (d) you may lose some or all of your tokens or other assets. You agree that you will have no recourse against anyone else for any losses due to the use of the Protocol. For example, these losses may arise from or relate to: (i) incorrect information; (ii) software or network failures; (iii) corrupted cryptocurrency wallet files; (iv) unauthorized access; (v) errors, mistakes, or inaccuracies; or (vi) third-party activities.

The Protocol does not collect any personal data, and your interaction with the Protocol will solely be through your public digital wallet address. Any personal or other data that you may make available in connection with the Protocol may not be private or secure.
