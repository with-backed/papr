pragma solidity ^0.8.13;

import "forge-std/StdJson.sol";
import "forge-std/Test.sol";
import "forge-std/Script.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";
import {Blitmap, Moonbird, Toadz, Dinos} from "src/heroTestnet/HeroNfts.sol";

/*
run with: forge script script/DeployPVPNFTs.s.sol:DeployPVPNFTs --private-key $PK --rpc-url $RPC
*/

contract DeployPaprHERONFT is Script, Test {
    using stdJson for string;

    struct AddressAmountPair {
        address addr;
        uint256 amount;
    }

    function run() public {
        vm.startBroadcast();

        Blitmap blitmap = new Blitmap();
        blitmap.claimOwnership();
        Moonbird moonbird = new Moonbird();
        moonbird.claimOwnership();
        Toadz toadz = new Toadz();
        toadz.claimOwnership();
        Dinos dinos = new Dinos();
        dinos.claimOwnership();

        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/script/mintPVPNFTs.json");
        string memory json = vm.readFile(path);

        // mint Blitmaps
        bytes memory rawPairs = json.parseRaw(".blitmap");
        AddressAmountPair[] memory pairs = abi.decode(rawPairs, (AddressAmountPair[]));

        mintForPairs(blitmap, pairs);

        // mint Moonbirds
        rawPairs = json.parseRaw(".moonbird");
        pairs = abi.decode(rawPairs, (AddressAmountPair[]));

        mintForPairs(moonbird, pairs);

        // mint Toadz
        rawPairs = json.parseRaw(".toadz");
        pairs = abi.decode(rawPairs, (AddressAmountPair[]));

        mintForPairs(toadz, pairs);

        //mint Dinos
        rawPairs = json.parseRaw(".dinos");
        pairs = abi.decode(rawPairs, (AddressAmountPair[]));

        mintForPairs(dinos, pairs);

        vm.stopBroadcast();
    }

    function mintForPairs(ERC721 nft, AddressAmountPair[] memory pairs) public {
        for (uint256 i = 0; i < pairs.length; i++) {
            address addr = pairs[i].addr;
            uint256 amount = pairs[i].amount;
            for (uint256 count = 0; count < amount; count++) {
                address(nft).call(abi.encodeWithSignature("mint(address)", addr));
            }
            assertEq(amount, nft.balanceOf(addr));
        }
    }
}
