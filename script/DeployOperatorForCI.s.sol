// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
 
import "../src/AccessControl.sol";
import "../src/Settings.sol";
import "../src/GasRebateManager.sol";
import "../src/BidManager.sol";
import "../src/DegenPool.sol";
import "../src/GasBank.sol";
import "../src/FeeCollector.sol";

// Note: MockMasterControl is in test/mocks/MockMasterControl.sol
import "../test/mocks/MockMasterControl.sol";

/// @notice Deploy minimal contracts required by the operator integration CI job,
/// and print a single-line JSON object containing the deployed addresses. The CI
/// job will parse this line to configure the operator.
contract DeployOperatorForCI is Script {
    function run() external returns (address[] memory) {
        vm.startBroadcast();

        AccessControl ac = new AccessControl();

        // Minimal platform contracts
        DegenPool degenPool = new DegenPool(ac);
        GasRebateManager gasRebate = new GasRebateManager(ac);
        BidManager bidManager = new BidManager(ac);
        // Deploy GasBank and FeeCollector so Settings constructor does not revert on zero addresses
        GasBank gasBank = new GasBank(ac);
        FeeCollector feeCollector = new FeeCollector(ac);
        Settings settings = new Settings(address(gasBank), address(degenPool), address(feeCollector), ac);

        // Deploy a simple mock MasterControl that exposes the PoolRebateReady event emitter
        MockMasterControl mockMaster = new MockMasterControl();

        // Build JSON
        string memory json = string(
            abi.encodePacked(
                '{"MasterControl":"', toHexString(address(mockMaster)),
                '","Settings":"', toHexString(address(settings)),
                '","GasRebate":"', toHexString(address(gasRebate)),
                '","BidManager":"', toHexString(address(bidManager)),
                '","DegenPool":"', toHexString(address(degenPool)),
                '"}'
            )
        );

        // Print JSON in a single console.log line so CI can parse it
        console.log(json);

        vm.stopBroadcast();

        address[] memory addrs = new address[](5);
        addrs[0] = address(mockMaster);
        addrs[1] = address(settings);
        addrs[2] = address(gasRebate);
        addrs[3] = address(bidManager);
        addrs[4] = address(degenPool);
        return addrs;
    }

    function toHexString(address account) internal pure returns (string memory) {
        bytes20 value = bytes20(account);
        bytes16 hexSymbols = "0123456789abcdef";
        bytes memory str = new bytes(42);
        str[0] = "0";
        str[1] = "x";
        for (uint i = 0; i < 20; i++) {
            str[2 + i * 2] = hexSymbols[uint8(value[i] >> 4)];
            str[3 + i * 2] = hexSymbols[uint8(value[i] & 0x0f)];
        }
        return string(str);
    }
}