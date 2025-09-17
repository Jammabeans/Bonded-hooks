// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/BidManager.sol";

/// @notice Small script to create demo bids. Keeps logic minimal to avoid stack pressure.
/// Usage:
///   forge script script/SeedBids.s.sol:SeedBids --rpc-url http://127.0.0.1:8545 --private-key $ANVIL_PRIVATE_KEY --broadcast -vvvv
contract SeedBids is Script {
    // Demo fallback address (used if BID_MANAGER env is not set)
    address internal constant DEMO_BID_MANAGER = 0x4c5859f0F772848b2D91F1D83E2Fe57935348029;

    function run() external {
        // For demo runs prefer the hardcoded address to avoid vm.envAddress reverting when env var is absent.
        address bidMgr = DEMO_BID_MANAGER;
        require(bidMgr != address(0), "missing BidManager address");

        BidManager bm = BidManager(payable(bidMgr));

        // Hardcode demo Anvil private keys for bidders (student demo; no env required)
        // Anvil account 1 private key:
        uint256 fkey1 = uint256(0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d);
        // Anvil account 2 private key:
        uint256 fkey2 = uint256(0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a);

        // Create a bid from FUNDING_KEY_1 (or from the broadcast key if not provided)
        if (fkey1 != 0) {
            vm.startBroadcast(fkey1);
            bm.createBid{value: 1 ether}(50, 100, 50);
            vm.stopBroadcast();
        } else {
            vm.startBroadcast();
            bm.createBid{value: 1 ether}(100, 50, 50);
            vm.stopBroadcast();
        }

        // Create an optional second bid from FUNDING_KEY_2 (skip if not provided)
        if (fkey2 != 0) {
            vm.startBroadcast(fkey2);
            bm.createBid{value: 2 ether}(0, 0, 100);
            vm.stopBroadcast();
        }
    }
}