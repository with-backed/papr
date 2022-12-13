## Overview

Papr facilitates NFT-backed loans. Borrowers deposit allowlisted NFT collateral and mint papr, which can then be exchanged on Uniswap for some other asset. Papr interest rates and the papr trading price are in a constant feedback loop. Interest rates are programmatically updated on chain as a function of papr’s trading price on Uniswap (the lower the trading price, the higher the interest to borrowers), and interest rates in turn affect the trading price, as borrowers open and close loans in response to rates.


![loop_diagram](https://user-images.githubusercontent.com/6678357/207438772-5bddff19-2b25-42d0-8eee-013fb8847fd2.png)

Interest accrues to the value of papr itself: over time, new borrowers are allowed less papr for the exact same collateral. When closing a loan, borrowers repay the exact same amount of papr that they minted. However, due to interest charges, it is expected that the market value of papr will have risen since they opened their loan.

To the extent that borrower incentives push the trading price of papr up over time, corresponding to these interest charges, papr holders are rewarded.

As an analogy, for those familiar with perpetuals, we can say that papr adapts the funding rate mechanism to set interest rates for loans and balance borrower and lender demand. In particular, papr tokens were heavily inspired by Squeeth, which pioneered perpetuals built on Uniswap V3 oracles and continuous, in-kind funding payments.

We *very strongly* encourage everyone to read our [whitepaper](https://backed.mirror.xyz/8SslPvU8of0h-fxoo6AybCpm51f30nd0qxPST8ep08c) to understand more!

## In Scope
Everything in `src/` is in scope. The main contracts are `PaprController` and `UniswapOracleFundingRateController`. The `NFTEDA` contracts are only used for liquidation auctions. `ReservoirOracleUnderwriter` is used for handling oracle messages for NFT values, which are used when minting debt (papr), withdrawing collateral, or liquidating vaults. 

## Out of Scope
There are a number of known limitations that are out of scope for the contest 
- It is possible for a malicious/faulty pool to be passed to UniswapOracleFundingRateController
- Many things can go wrong in PaprController and NFTEDA if a malicious/faulty NFT is used
- Many things can go wrong in NFTEDA if a malicious/faulty ERC20 is used for payment asset
- Many things can go wrong in PaprController if a malicious/faulty ERC20 is used for `underlying`
- Additionally, there are myriad possibilities for the state of the system: Target values, Mark values, oracle prices, Uniswap liquidity, and more. We are open to hearing about possible adverse scenarios, but be aware that we are aware of many and are OK with the possibility. 


## Running code 
`foundryup` + `forge install` + `forge test` will get you up and going. (More info on Foundry [here](https://github.com/foundry-rs/foundry)). Most of the PaprController tests are forking tests: relying on real chain state. To get these working, add an RPC url value (e.g. from Alchemy or Infura) for `MAINNET_RPC_URL` in a `.env` file. 
