 // SPDX-License-Identifier: MIT
 pragma solidity ^0.8.20;
 
 import "forge-std/Script.sol";
 import "../src/PointsCommand.sol";
 import "../src/BidManager.sol";
 import "../src/AccessControl.sol";
 import "../src/MasterControl.sol";
 
 /// @notice Deploy remaining platform contracts that may be large (PointsCommand, BidManager).
 /// Reads env vars set by previous deploy step:
 /// - ACCESS_CONTROL
 /// - MASTER_CONTROL
 /// Prints a single-line JSON containing the deployed addresses.
 contract DeployPlatformFinish is Script {
     function run() external returns (address[] memory) {
         address accessControlAddr = vm.envAddress("ACCESS_CONTROL");
         address masterControlAddr = vm.envAddress("MASTER_CONTROL");
         require(accessControlAddr != address(0), "ACCESS_CONTROL env not set");
         require(masterControlAddr != address(0), "MASTER_CONTROL env not set");
 
         vm.startBroadcast();
 
         AccessControl accessControl = AccessControl(accessControlAddr);
         MasterControl masterControl = MasterControl(masterControlAddr);
 
         PointsCommand pointsCommand = new PointsCommand();
         BidManager bidManager = new BidManager(accessControl);
 
         // Grant master role and approve points command
         accessControl.grantRole(masterControl.ROLE_MASTER(), tx.origin);
         masterControl.approveCommand(bytes32(0), address(pointsCommand), "PointsCommand");
 
         // Build JSON and print
         bytes memory jb = abi.encodePacked("{");
         jb = abi.encodePacked(jb, '"PointsCommand":"', toHexString(address(pointsCommand)), '"');
         jb = abi.encodePacked(jb, ',"BidManager":"', toHexString(address(bidManager)), '"');
         jb = abi.encodePacked(jb, "}");
         console.log(string(jb));
 
         vm.stopBroadcast();
 
         address[] memory out = new address[](2);
         out[0] = address(pointsCommand);
         out[1] = address(bidManager);
         return out;
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