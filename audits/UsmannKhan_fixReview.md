# papr Fix Review
papr engaged Usmann Khan to conduct a fix review of their changes made in response to findings from their [Code4rena contest](https://code4rena.com/contests/2022-12-papr-contest). papr has sufficiently resolved all of the identified issues. 

## Project Methodology
Work involved in the fix review involved:
 - A review of all medium and high findings presented in the original Code4rena contest.
 - A review of all code changes made to address the findings, and their sufficiency in resolving the related findings.
 - A manual review of the post-change codebase.

## Project Targets

papr Protocol
 - Repo: https://github.com/with-backed/papr/
 - Commit [`1e6edd629012266b6ff8b041f3070ece7f520da9`](https://github.com/with-backed/papr/tree/1e6edd629012266b6ff8b041f3070ece7f520da9)

## Summary of Fix Review Results

| ID | Title | Status |
| --- | --- | --- |
| [H-01] | [Liquidation Auctions may improperly distribute funds](#h-01-liquidation-auctions-may-improperly-distribute-funds) | Resolved 🟢 |
| [H-02] | [PaprController is vulnerable to reentrancy attacks](#h-02-paprcontroller-is-vulnerable-to-reentrancy-attacks) | Resolved 🟢 |
| [H-03] | [Collateral sent To papr via transferFrom is credited to the wrong account](#h-03-collateral-sent-to-papr-via-transferfrom-is-credited-to-the-wrong-account) | Resolved 🟢 |
| [H-04] | [Some users may be liquidatable immediately on borrow](#h-04-some-users-may-be-liquidatable-immediately-on-borrow) | Resolved 🟢 |
| [M-01] | [Calls to swap are made without a deadline check](#m-01-calls-to-swap-are-made-without-a-deadline-check) | Resolved 🟢 |
| [M-02] | [Users may circumvent the collateral allowlist](#m-02-users-may-circumvent-the-collateral-allowlist) | Resolved 🟢 |
| [M-03] | [Pending debt repayment transactions can be forced to fail](#m-03-pending-debt-repayment-transactions-can-be-frontrun-and-forced-to-fail) | Resolved 🟢 |
| [M-04] | [Incorrect usage of safeTransferFrom traps fees in PaprController](#m-04-incorrect-usage-of-safetransferfrom-traps-fees-in-papr-controller) | Resolved 🟢 |
| [M-05] | [Users may be debited twice when reducing debt for someone else](#m-05-users-may-be-debited-twice-when-reducing-debt-for-someone-else) | Resolved 🟢 |
| [M-06] | [buyAndReduceDebt erroneously charges fees to PaprController](#m-06-buyandreducedebt-erroneously-charges-fees-to-paprcontroller) | Resolved 🟢 |
| [M-07] | [Debt may be erroneously cleared in the case of oracle failure](#m-07-debt-may-be-erroneously-cleared-in-the-case-of-oracle-failure) | Resolved 🟢 |
| [M-08] | [Incorrect accounting when liquidating a user's final NFT in a loan](#m-08-incorrect-accounting-when-liquidating-a-users-final-nft-in-a-loan) | Resolved 🟢 |

## [H-01] Liquidation Auctions may improperly distribute funds
## Status: Resolved 🟢
### Description

The papr protocol relies on liquidation auctions to recover funds when a loan goes beyond the LTV limit. When the final collateral NFT for a particular loan is sold in a liquidation auction, the debt for that debtor-collateral pair is set to 0.

The intended behavior is to set the debt to 0 when an NFT from a particular loan is liquidated AND all other NFTs from that loan have already been liquidated.

However, the protocol mistakenly sets the debt to 0 if an NFT from a loan is liquidated AND all other NFTs are (currently in liquidation OR have been liquidated).

This leads to an error where if all NFTs from a loan are in liquidation auctions, buying any single one allows users to claim the rest for free.

```solidity
info.count -= 1;
```
###### A snipped of `startLiquidationAuction` [function](https://github.com/with-backed/papr/blob/9528f2711ff0c1522076b9f93fba13f88d5bd5e6/src/PaprController.sol#L326) in PaprController.sol
A loan's `count` is reduced at the beginning of an auction

```solidity
uint256 collateralValueCached = underwritePriceForCollateral(
    auction.auctionAssetContract, ReservoirOracleUnderwriter.PriceKind.TWAP, oracleInfo
) * _vaultInfo[auction.nftOwner][auction.auctionAssetContract].count;
bool isLastCollateral = collateralValueCached == 0;

...

if (isLastCollateral && remaining != 0) {
    /// there will be debt left with no NFTs, set it to 0
    _reduceDebtWithoutBurn(auction.nftOwner, auction.auctionAssetContract, remaining);
}
```
###### A condensed snippet of the `purchaseLiquidationAuctionNFT` [function](https://github.com/with-backed/papr/blob/9528f2711ff0c1522076b9f93fba13f88d5bd5e6/src/PaprController.sol#L264) in PaprController.sol.
The `collateralValueCached` value is multiplied by the `count` variable which is decreased at the beginning of each auction. `count` is 0 when all auctions have *begun*. When `collateralValueCached` is 0 for a purchase, all debt is cleared at the purchase's end.

### Fix Analysis

The issue has been [resolved](https://github.com/with-backed/papr/pull/103). The papr team updated the `VaultInfo` struct to add an `auctionCount` variable. Decrements to the original `count` value are now accumulated into `auctionCount` and only reduced from there when an auction ends. Debt is now summarily cleared only when the final auction ends.

## [H-02] PaprController is vulnerable to reentrancy attacks
## Status: Resolved 🟢
### Description

There were several instances where an `ERC721` was `safeTransfer`red in the middle of a series of guards and state-changing operations. This created the opportunity for reentrancy attacks, as the `safeTransfer` operation transfers control to a callback on the receiver.

```solidity
function purchaseLiquidationAuctionNFT(
    Auction calldata auction,
    uint256 maxPrice,
    address sendTo,
    ReservoirOracleUnderwriter.OracleInfo calldata oracleInfo
) external override {
    uint256 collateralValueCached = underwritePriceForCollateral(
        auction.auctionAssetContract, ReservoirOracleUnderwriter.PriceKind.TWAP, oracleInfo
    ) * _vaultInfo[auction.nftOwner][auction.auctionAssetContract].count;
    bool isLastCollateral = collateralValueCached == 0;

    uint256 debtCached = _vaultInfo[auction.nftOwner][auction.auctionAssetContract].debt;
    uint256 maxDebtCached = isLastCollateral ? debtCached : _maxDebt(collateralValueCached, updateTarget());
    /// anything above what is needed to bring this vault under maxDebt is considered excess
    uint256 neededToSaveVault = maxDebtCached > debtCached ? 0 : debtCached - maxDebtCached;
    uint256 price = _purchaseNFTAndUpdateVaultIfNeeded(auction, maxPrice, sendTo);
```
###### A snippet of the `purchaseLiquidationAuctionNFT` [function](https://github.com/with-backed/papr/blob/9528f2711ff0c1522076b9f93fba13f88d5bd5e6/src/PaprController.sol#L264-L279) in PaprController.sol
When purchasing an NFT in a liquidation auction, values were calculated and cached before handing control to the receiver via `_purchaseNFTAndUpdateVaultIfNeeded`, which eventually performs an ERC721 `safeTransfer`. An attacker could make updates to these variables and return to this point, where `purchaseLiquidationAuctionNFT` would proceed and make further updates based on the _cached_ values rather than the actual ones.

```solidity
uint16 newCount;
unchecked {
    newCount = _vaultInfo[msg.sender][collateral.addr].count - 1;
    _vaultInfo[msg.sender][collateral.addr].count = newCount;
}

// allows for onReceive hook to sell and repay debt before the
// debt check below
collateral.addr.safeTransferFrom(address(this), sendTo, collateral.id);

uint256 debt = _vaultInfo[msg.sender][collateral.addr].debt;
uint256 max = _maxDebt(oraclePrice * newCount, cachedTarget);

if (debt > max) {
    revert IPaprController.ExceedsMaxDebt(debt, max);
}
```
###### A snippet of the `_removeCollateral` [function](https://github.com/with-backed/papr/blob/9528f2711ff0c1522076b9f93fba13f88d5bd5e6/src/PaprController.sol#L436-L451) in PaprController.sol
In a separate attack, one could have used the `safeTransfer` called in the remove collateral process. Here, the debt check was done after reducing the `count` and transferring out the ERC721. This allows for the attacker to leverage this inconsistency via a liquidation auction to clear their debt before returning control flow to the above check. 

### Fix analysis

This issue has been resolved [1](https://github.com/with-backed/papr/pull/99) [2](https://github.com/with-backed/papr/pull/102) [3](https://github.com/with-backed/papr/pull/115). In the case of both the `_removeCollateral` and `purchaseLiquidationAuctionNFT` functions, the external call has been moved such that the function follows the checks-effects-interactions pattern.

## [H-03] Collateral sent to papr via `transferFrom` is credited to the wrong account
## Status: Resolved 🟢
### Description
When an authorized agent transfers an NFT to papr on behalf of its owner, papr credits the deposit to the agent rather than the owner.

```solidity
function onERC721Received(address from, address, uint256 _id, bytes calldata data)
    external
    override
    returns (bytes4)
{
    IPaprController.OnERC721ReceivedArgs memory request = abi.decode(data, (IPaprController.OnERC721ReceivedArgs));

    IPaprController.Collateral memory collateral = IPaprController.Collateral(ERC721(msg.sender), _id);

    _addCollateralToVault(from, collateral);
```
###### A snippet of the `onERC721Received` [function](https://github.com/with-backed/papr/blob/9528f2711ff0c1522076b9f93fba13f88d5bd5e6/src/PaprController.sol#L159-L168) in PaprController.sol

The `onERC721Received` hook in `PaprController.sol` incorrectly sets the `from` address to the value of the first input parameter, rather than the second.

[EIP-721](https://eips.ethereum.org/EIPS/eip-721) defines `onERC721Received` as:

`function onERC721Received(address _operator, address _from, uint256 _tokenId, bytes _data) external returns(bytes4);`

As a result, operators sending NFTs to papr on behalf of owners will be credited with deposits instead of the actual owners.

### Fix Analysis

This issue has been [resolved](https://github.com/with-backed/papr/pull/97). The signature of `onERC721Received` was changed to:

`function onERC721Received(address, address from, uint256 _id, bytes calldata data)`

NFT owners will now be credited with deposits, even if an authorized operator initiated the transfer on the owner's behalf.

## [H-04] Some users may be liquidatable immediately on borrow
## Status: Resolved 🟢
### Description

In papr the maximum borrow amount and the liquidation threshold are the same. This means that a max loan may be liquidated even if the price hasn't moved since the loan was taken out. Bot operators may take advantage of this by watching the mempool and immediately liquidating any unsuspecting user who has taken out a maximum loan, in the same block as the loan was taken out.

```solidity
if (newDebt > max) revert IPaprController.ExceedsMaxDebt(newDebt, max);
```
###### A snippet of the `_increaseDebt` [function](https://github.com/with-backed/papr/blob/9528f2711ff0c1522076b9f93fba13f88d5bd5e6/src/PaprController.sol#L471) in PaprController.sol
Debt can be increased up until, and including, where `newDebt == max`.

```solidity
if (info.debt < _maxDebt(oraclePrice * info.count, cachedTarget)) {
    revert IPaprController.NotLiquidatable();
}
```
###### A snippet of the `startLiquidationAuction` [function](https://github.com/with-backed/papr/blob/9528f2711ff0c1522076b9f93fba13f88d5bd5e6/src/PaprController.sol#L317-L319) in PaprController.sol
Positions can be liquidated as long as `debt >= maxDebt`
### Fix Analysis
This issue has been [resolved](https://github.com/with-backed/papr/pull/106). The `_increaseDebt` function was changed such that debt can only be incurred if the final debt is strictly less than the maximum debt. It is now the case that a price change must occur for any position to be liquidated.

## [M-01] Calls to swap() are made without a deadline check
## Status: Resolved 🟢
### Description
In some cases it is disadvantageous to deny users the ability to set a deadline when queueing a DEX swap. Consider the case where a user sends a transaction into the mempool that would cause a swap, but which for whatever reason does not make it on-chain. An attacker may store this transaction until the market price changes such that the transaction incurs positive slippage, and then execute the transaction and claim this slippage for themselves.

### Fix analysis
This issue has been [resolved](https://github.com/with-backed/papr/pull/109). A deadline parameter was added to all external functions that may cause swaps. This parameter is enforced in the `UniswapHelpers.swap` function.

## [M-02] Users may circumvent the collateral allowlist
The `PaprController` contract uses an allowlist to gate collateral types that may be used to take out debt. The allowlist is checked in `_addCollateralToVault`. However, it may be the case that a user has added collateral to the vault which was allowed at the time, but is not anymore. In these cases, the protocol continues to allow the user to take out debt using this collateral.

```solidity
function _addCollateralToVault(address account, IPaprController.Collateral memory collateral) internal {
    if (!isAllowed[address(collateral.addr)]) {
        revert IPaprController.InvalidCollateral();
    }
```
###### A snippet of the `_addCollateralToVault` [function](https://github.com/with-backed/papr/blob/9528f2711ff0c1522076b9f93fba13f88d5bd5e6/src/PaprController.sol#L100) in PaprController

```solidity
function _increaseDebt(
	address account,
	ERC721 asset,
	address mintTo,
	uint256 amount,
	ReservoirOracleUnderwriter.OracleInfo memory oracleInfo
) internal {
	uint256 cachedTarget = updateTarget();

	uint256 newDebt = _vaultInfo[account][asset].debt + amount;
	uint256 oraclePrice =
		underwritePriceForCollateral(asset, ReservoirOracleUnderwriter.PriceKind.LOWER, oracleInfo);

	uint256 max = _maxDebt(_vaultInfo[account][asset].count * oraclePrice, cachedTarget);

	if (newDebt > max) revert IPaprController.ExceedsMaxDebt(newDebt, max);

	if (newDebt >= 1 << 200) revert IPaprController.DebtAmountExceedsUint200();

	_vaultInfo[account][asset].debt = uint200(newDebt);
	PaprToken(address(papr)).mint(mintTo, amount);

	emit IncreaseDebt(account, asset, amount);
}
```
###### The `_increaseDebt` [function](https://github.com/with-backed/papr/blob/9528f2711ff0c1522076b9f93fba13f88d5bd5e6/src/PaprController.sol#L456-L479) in PaprController.sol

While the `_addCollateralToVault` function checks the `isAllowed` mapping, the `_increaseDebt` function does not.

### Fix Analysis
This issue has been [resolved](https://github.com/with-backed/papr/pull/94). The papr team added a check to the `_increaseDebt` that ensures the collateral asset is in the allowlist.

## [M-03] Pending debt repayment transactions can be frontrun and forced to fail
## Status: Resolved 🟢
### Description
It is possible to reduce one's debt to the papr protocol by calling `reduceDebt`. However, the `reduceDebt` function accepts an exact amount to reduce one's debt by and reverts if you attempt to reduce your debt by a value greater than your actual debt. Additionally, anyone may repay debt on anyone else's behalf. This opens the protocol to a grieving attack.

For example:
- Alice is 100papr in debt.
- Alice notices her collateral is decreasing in value and decides to pay back her entire loan and withdraw her collateral.
- Alice calls `reduceDebt` with a value of 100.
- Bob, watching the mempool, sees this and frontruns Alice's transaction with his own where he reduces Alice's debt by 1e-18.
- Alice's transaction lands after Bob's and fails because her debt is now only 99.9999... and she tried to reduce it by 100. 
- In extreme cases, this may coincide with further decline of Alice's collateral value and lead to her loan being liquidated.
  
### Fix Analysis
This issue has been [resolved](https://github.com/with-backed/papr/pull/104/). The `buyAndReduceDebt` and `reduceDebt` functions have been changed to use the minimum of current debt and the specified amount, instead of trying to just use the specified amount or revert.

## [M-04] Incorrect usage of safeTransferFrom traps fees in Papr Controller
## Status: Resolved 🟢
### Description

The `sendPaprFromAuctionFees` function attempts to `transferFrom` an ERC20 from itself, despite never granting an `approval` balance to itself. This transfer would fail if called. However, the `sendPaprFromAuctionFees` function is unused.

### Fix Analysis
This issue has been [resolved](https://github.com/with-backed/papr/pull/107). The relevant (unused) function has been removed.

## [M-05] Users may be debited twice when reducing debt for someone else
## Status: Resolved 🟢
### Description

The `buyAndReduceDebt` function allows a user to perform a swap from `underlying` to `papr` and use the proceeds to pay down the debt of a specified account. When a user attempts to use this to pay down their own debt, they are credited the output of the swap, and then that same output is burned from their account.

However, when a user attempts to use this function to pay down someone _else's_ debt, the proceeds of the swap are sent to the debt owner and the papr is burned from the acting user. In this case the acting user would first pay in `underlying` to buy papr for the debtor, but then they would also have papr burned from themselves. The impact is that the user pays double the value necessary to reduce the debt.

```solidity
function buyAndReduceDebt(address account, ERC721 collateralAsset, IPaprController.SwapParams calldata params)
    external
    override
    returns (uint256)
{
    bool hasFee = params.swapFeeBips != 0;

    (uint256 amountOut, uint256 amountIn) = UniswapHelpers.swap(
        pool,
        account,
        token0IsUnderlying,
        params.amount,
        params.minOut,
        params.sqrtPriceLimitX96,
        abi.encode(msg.sender)
    );;

    if (hasFee) {
        underlying.transfer(params.swapFeeTo, amountIn * params.swapFeeBips / BIPS_ONE);
    }

    _reduceDebt({account: account, asset: collateralAsset, burnFrom: msg.sender, amount: amountOut});

    return amountOut;
}
```
###### A snippet of the buyAndReduceDebt [function](https://github.com/with-backed/papr/blob/9528f2711ff0c1522076b9f93fba13f88d5bd5e6/src/PaprController.sol#L208-L223) in PaprController.sol.
The swap proceeds are sent to `account`, but the input is paid by `msg.sender`. Later, debt is reduced and the repayment is done by burning papr from `msg.sender`.

### Fix Analysis
This issue has been [resolved](https://github.com/with-backed/papr/pull/98). The call to `UniswapHelpers.swap` was changed such that the output is credited to `msg.sender`. The papr burned in `_reduceDebt` is now offset by the credit outputted by `swap`.

## [M-06] `buyAndReduceDebt` erroneously charges fees to `PaprController`
## Status: Resolved 🟢
### Description
The `buyAndReduceDebt` function allows the caller to specify a fee percentage and fee recipient. The function is intended to swap papr for `underlying`, send a portion of the `underlying` received to the fee recipient, and use the rest to pay down debt.

However, the function erroneously withdraws the fee amount from itself (PaprController) instead of from the caller. Because PaprController is not designed to hold any amount of underlying, this call will most likely revert.

```solidity
if (hasFee) {
    underlying.transfer(params.swapFeeTo, amountIn * params.swapFeeBips / BIPS_ONE);
}
```
###### A snippet of the buyAndReduceDebt [function](https://github.com/with-backed/papr/blob/9528f2711ff0c1522076b9f93fba13f88d5bd5e6/src/PaprController.sol#L208-L223) in PaprController.sol.

The fee amount is transferred to `params.swapFeeTo` from the current contract's balance (aka the PaprController's balance).

### Fix Analysis
This issue has been [resolved](https://github.com/with-backed/papr/pull/93). The call to `transfer` has been replaced to a call to `transferFrom` where the funds are sent from `msg.sender` to `params.swapFeeTo`.

## [M-07] Debt may be erroneously cleared in the case of oracle failure
## Status: Resolved 🟢
### Description

When purchasing an NFT from a liquidation auction, papr will summarily dismiss all of the NFT owner's debt at the end of the liquidation if it is their last token in the loan. The last-token check is done by proxy via the condition `collateralValueCached == 0`.

However, if the Reservoir oracle fails and returns that the tokens have 0 value, this check may return true even if the owner has many tokens remaining in the loan. For example, (0 tokens of value 10) and (10 tokens of value 0) both have a `collateralValueCached` of 0.

```solidity
function purchaseLiquidationAuctionNFT(
    Auction calldata auction,
    uint256 maxPrice,
    address sendTo,
    ReservoirOracleUnderwriter.OracleInfo calldata oracleInfo
) external override {
    uint256 collateralValueCached = underwritePriceForCollateral(
        auction.auctionAssetContract, ReservoirOracleUnderwriter.PriceKind.TWAP, oracleInfo
    ) * _vaultInfo[auction.nftOwner][auction.auctionAssetContract].count;
    bool isLastCollateral = collateralValueCached == 0;

...

if (isLastCollateral && remaining != 0) {
    /// there will be debt left with no NFTs, set it to 0
    _reduceDebtWithoutBurn(auction.nftOwner, auction.auctionAssetContract, remaining);
}
```
###### A condensed snippet of the `purchaseLiquidationAuctionNFT` [function](https://github.com/with-backed/papr/blob/9528f2711ff0c1522076b9f93fba13f88d5bd5e6/src/PaprController.sol#L264-L273) in PaprController.sol.

### Fix Analysis
This issue has been [resolved](https://github.com/with-backed/papr/pull/95). The guard was changed to directly check if `count == 0` instead of the derived product of `count` and price.

## [M-08] Incorrect accounting when liquidating a user's final NFT in a loan
## Status: Resolved 🟢
### Description
When an NFT is purchased in a liquidation auction, the proceeds are used to cover the original borrower's debt. This is done by paying back the protocol up until the loan is at the correct LTV. The borrower's current debt is compared to their maximum allowed debt, and auction proceeds are used to cover the difference.

In the case of liquidating a user's final NFT the maximum allowed debt should be set to 0, because the user will have no collateral left. However, the maximum debt was erroneously set to be equal to the current debt.

```solidity
uint256 maxDebtCached = isLastCollateral ? debtCached : _maxDebt(collateralValueCached, updateTarget());
```
###### A condensed snippet of the `purchaseLiquidationAuctionNFT` [function](https://github.com/with-backed/papr/blob/9528f2711ff0c1522076b9f93fba13f88d5bd5e6/src/PaprController.sol#L276) in PaprController.sol.
### Fix Analysis
The issue has been [resolved](https://github.com/with-backed/papr/pull/95). The value of `maxDebtCached` has been changed to be `0` in the case of liquidating a user's last collateral.

