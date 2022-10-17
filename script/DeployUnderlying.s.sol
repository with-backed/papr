pragma solidity ^0.8.13;

import "forge-std/StdJson.sol";
import "forge-std/Test.sol";
import "forge-std/Script.sol";
import {PVPUSDC} from "src/pvp/PVPUSDC.sol";

/*
run with: forge script script/DeployUnderlying.s.sol:DeployUnderlying --private-key $PK --rpc-url $RPC
*/

contract DeployUnderlying is Script, Test {
    using stdJson for string;

    struct AddressAmountPair {
        address addr;
        uint256 amount;
    }

    function run() public {
        vm.startBroadcast();

        PVPUSDC pvpUSDC = new PVPUSDC();
        pvpUSDC.claimOwnership();

        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/script/mintUnderlying.json");
        string memory json = vm.readFile(path);
        bytes memory rawPairs = json.parseRaw(".addressAmountPairs");
        AddressAmountPair[] memory pairs = abi.decode(
            rawPairs,
            (AddressAmountPair[])
        );
        for (uint256 i = 0; i < pairs.length; i++) {
            address addr = pairs[i].addr;
            uint256 amount = pairs[i].amount;
            pvpUSDC.mint(addr, amount);
            assertEq(amount, pvpUSDC.balanceOf(addr));
        }

        vm.stopBroadcast();
    }
}
