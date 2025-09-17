// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/Bonding.sol";

/// @notice SeedBonds script — deposits a demo native bond into Bonding for PointsCommand target.
/// Usage:
///   forge script script/SeedBonds.s.sol:SeedBonds --rpc-url http://127.0.0.1:8545 --private-key $ANVIL_PRIVATE_KEY --broadcast -vvvv
contract SeedBonds is Script {
    address internal constant DEMO_BONDING = 0x59b670e9fA9D0A427751Af201D676719a970857b;
    address internal constant DEMO_POINTS = 0x809d550fca64d94Bd9F66E60752A544199cfAC3D;

    function run() external {
        address bondingAddr = vm.envAddress("BONDING");
        address pointsAddr = vm.envAddress("POINTS_COMMAND");

        if (bondingAddr == address(0)) bondingAddr = DEMO_BONDING;
        if (pointsAddr == address(0)) pointsAddr = DEMO_POINTS;

        require(bondingAddr != address(0) && pointsAddr != address(0), "missing addresses");

        Bonding bonding = Bonding(payable(bondingAddr));

        // Use FUNDING_KEY_1 if available, else use the broadcast key
        uint256 fkey1 = vm.envUint("FUNDING_KEY_1");
        if (fkey1 != 0) {
            vm.startBroadcast(fkey1);
            bonding.depositBondNative{value: 0.5 ether}(pointsAddr);
            vm.stopBroadcast();
        } else {
            vm.startBroadcast();
            bonding.depositBondNative{value: 0.5 ether}(pointsAddr);
            vm.stopBroadcast();
        }
    }
}