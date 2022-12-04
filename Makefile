deploy-controller :; source .env && forge script script/DeployPaprController.s.sol:DeployPaprController --rpc-url $${GOERLI_RPC_URL}  --private-key $${PRIVATE_KEY} --broadcast
lp :; source .env && forge script script/actions/UniswapLP.s.sol:UniswapLP --rpc-url $${GOERLI_RPC_URL}  --private-key $${PRIVATE_KEY} --broadcast
max-borrow :; source .env && forge script script/actions/MintNFTAndBorrowMax.s.sol:MintNFTAndBorrowMax --rpc-url $${GOERLI_RPC_URL}  --private-key $${PRIVATE_KEY} --broadcast
start-auction :; source .env && forge script script/actions/StartAuction.s.sol:StartAuction --rpc-url $${GOERLI_RPC_URL}  --private-key $${PRIVATE_KEY} --broadcast
purchase-auction-nft :; source .env && forge script script/actions/PurchaseAuctionNFT.s.sol:PurchaseAuctionNFT --rpc-url $${GOERLI_RPC_URL}  --private-key $${PRIVATE_KEY} --broadcast
debug :; forge test -w -m testDebug -vvvv