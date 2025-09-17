 // SPDX-License-Identifier: MIT
 pragma solidity ^0.8.20;
 
 import "forge-std/Script.sol";
 
 import "../src/AccessControl.sol";
 import "../src/MemoryCard.sol";
 import "../src/FeeCollector.sol";
 import "../src/GasBank.sol";
 import "../src/DegenPool.sol";
 import "../src/Settings.sol";
 import "../src/ShareSplitter.sol";
 import "../src/Bonding.sol";
 import "../src/PrizeBox.sol";
 import "../src/Shaker.sol";
 import "../src/PointsCommand.sol";
 import "../src/BidManager.sol";
 import "../test/mocks/MockAVS.sol";
 import "v4-core/interfaces/IPoolManager.sol";
 import "../src/PoolLaunchPad.sol";
 import "../src/MasterControl.sol";
 
 /// @notice Deploy platform contracts and wire them. Reads required core addresses from environment:
 /// - MANAGER
 /// - ACCESS_CONTROL
 /// - POOL_LAUNCHPAD
 /// - MASTER_CONTROL
 /// Prints a single-line JSON with deployed platform addresses.
 contract DeployPlatform is Script {
     function run() external returns (address[] memory) {
         // Expect env vars to be set by the caller
         address mgr = vm.envAddress("MANAGER");
         address accessControlAddr = vm.envAddress("ACCESS_CONTROL");
         address poolLaunchPadAddr = vm.envAddress("POOL_LAUNCHPAD");
         address masterControlAddr = vm.envAddress("MASTER_CONTROL");
     
         require(mgr != address(0), "MANAGER env not set");
         require(accessControlAddr != address(0), "ACCESS_CONTROL env not set");
         require(poolLaunchPadAddr != address(0), "POOL_LAUNCHPAD env not set");
         require(masterControlAddr != address(0), "MASTER_CONTROL env not set");
     
         // Begin broadcast so deployments are posted to the node
         vm.startBroadcast();
     
         // Delegate the heavy lifting to an internal function so the public run() has fewer locals
         address[] memory out = _deployAndWire(mgr, accessControlAddr, poolLaunchPadAddr, masterControlAddr);
     
         vm.stopBroadcast();
         return out;
     }
     
     function _deployAndWire(address mgr, address accessControlAddr, address poolLaunchPadAddr, address masterControlAddr) internal returns (address[] memory) {
         // Deploy contracts into a compact address array to keep per-function locals small.
         address[] memory addrs = _deployContracts(accessControlAddr);
     
         // Perform wiring and role grants using inline casts (minimize local variables).
         AccessControl(accessControlAddr).grantRole(GasBank(payable(addrs[1])).ROLE_GAS_BANK_ADMIN(), tx.origin);
         AccessControl(accessControlAddr).grantRole(FeeCollector(payable(addrs[0])).ROLE_FEE_COLLECTOR_ADMIN(), tx.origin);
         AccessControl(accessControlAddr).grantRole(DegenPool(payable(addrs[2])).ROLE_DEGEN_ADMIN(), tx.origin);
         AccessControl(accessControlAddr).grantRole(BidManager(payable(addrs[3])).ROLE_BID_MANAGER_ADMIN(), tx.origin);
         AccessControl(accessControlAddr).grantRole(ShareSplitter(payable(addrs[5])).ROLE_SHARE_ADMIN(), tx.origin);
         AccessControl(accessControlAddr).grantRole(Bonding(payable(addrs[6])).ROLE_BONDING_ADMIN(), tx.origin);
         AccessControl(accessControlAddr).grantRole(Bonding(payable(addrs[6])).ROLE_BONDING_PUBLISHER(), tx.origin);
         AccessControl(accessControlAddr).grantRole(Bonding(payable(addrs[6])).ROLE_BONDING_WITHDRAWER(), tx.origin);
     
         GasBank(payable(addrs[1])).setShareSplitter(addrs[5]);
         FeeCollector(payable(addrs[0])).setSettings(addrs[4]);
     
         BidManager(payable(addrs[3])).setSettlementRole(addrs[7], true);
         DegenPool(payable(addrs[2])).setSettlementRole(addrs[7], true);
     
         Bonding(payable(addrs[6])).setAuthorizedPublisher(masterControlAddr, true);
         Bonding(payable(addrs[6])).setAuthorizedWithdrawer(addrs[1], true);
         Bonding(payable(addrs[6])).setAuthorizedWithdrawer(addrs[5], true);
     
         // Grant PrizeBox/Shaker admin roles before calling setShaker
         AccessControl(accessControlAddr).grantRole(PrizeBox(payable(addrs[8])).ROLE_PRIZEBOX_ADMIN(), tx.origin);
         AccessControl(accessControlAddr).grantRole(Shaker(payable(addrs[9])).ROLE_SHAKER_ADMIN(), tx.origin);
         PrizeBox(payable(addrs[8])).setShaker(addrs[9]);
     
         AccessControl(accessControlAddr).grantRole(MasterControl(masterControlAddr).ROLE_MASTER(), tx.origin);
         MasterControl(masterControlAddr).approveCommand(bytes32(0), addrs[10], "PointsCommand");
     
         // Build JSON with platform addresses (matching DeployForLocal expectation)
         bytes memory jb = abi.encodePacked("{");
         jb = abi.encodePacked(jb, '"FeeCollector":"', toHexString(addrs[0]), '"');
         jb = abi.encodePacked(jb, ',"GasBank":"', toHexString(addrs[1]), '"');
         jb = abi.encodePacked(jb, ',"DegenPool":"', toHexString(addrs[2]), '"');
         jb = abi.encodePacked(jb, ',"Settings":"', toHexString(addrs[4]), '"');
         jb = abi.encodePacked(jb, ',"ShareSplitter":"', toHexString(addrs[5]), '"');
         jb = abi.encodePacked(jb, ',"Bonding":"', toHexString(addrs[6]), '"');
         jb = abi.encodePacked(jb, ',"MockAVS":"', toHexString(addrs[7]), '"');
         jb = abi.encodePacked(jb, ',"PrizeBox":"', toHexString(addrs[8]), '"');
         jb = abi.encodePacked(jb, ',"Shaker":"', toHexString(addrs[9]), '"');
         jb = abi.encodePacked(jb, ',"PointsCommand":"', toHexString(addrs[10]), '"');
         jb = abi.encodePacked(jb, ',"BidManager":"', toHexString(addrs[3]), '"');
         jb = abi.encodePacked(jb, "}");
     
         string memory json = string(jb);
         // Print single-line JSON for helpers
         console.log(json);
     
         return addrs;
     }
     
     function _deployContracts(address accessControlAddr) internal returns (address[] memory addrs) {
         // Split deployments into two phases to limit live local variables per function.
         addrs = _deployContractsPrimary(accessControlAddr);
         _deployContractsSecondary(accessControlAddr, addrs);
         return addrs;
     }
     
     function _deployContractsPrimary(address accessControlAddr) internal returns (address[] memory addrs) {
         AccessControl accessControl = AccessControl(accessControlAddr);
         addrs = new address[](11);
     
         // Primary deploys (simple single-arg constructors)
         addrs[0] = address(new FeeCollector(accessControl));
         addrs[1] = address(new GasBank(accessControl));
         addrs[2] = address(new DegenPool(accessControl));
         addrs[3] = address(new BidManager(accessControl));
         addrs[6] = address(new Bonding(accessControl));
         addrs[7] = address(new MockAVS());
         addrs[10] = address(new PointsCommand());
     
         return addrs;
     }
     
     function _deployContractsSecondary(address accessControlAddr, address[] memory addrs) internal {
         AccessControl accessControl = AccessControl(accessControlAddr);
         // Secondary deploys that depend on earlier addresses
         addrs[4] = address(new Settings(address(addrs[1]), address(addrs[2]), address(addrs[0]), accessControl));
         addrs[5] = address(new ShareSplitter(addrs[4], accessControl));
         addrs[8] = address(new PrizeBox(accessControl, addrs[7]));
         addrs[9] = address(new Shaker(accessControl, addrs[5], addrs[8], addrs[7]));
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