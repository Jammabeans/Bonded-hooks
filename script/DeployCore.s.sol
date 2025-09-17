// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/AccessControl.sol";
import "../src/PoolLaunchPad.sol";
import "../src/MasterControl.sol";
import "../src/Create2Factory.sol";
import "v4-core/interfaces/IPoolManager.sol";
import "../lib/v4-periphery/src/utils/HookMiner.sol";
import "v4-core/libraries/Hooks.sol";

/// @notice Deploy the core project contracts that require an existing PoolManager:
/// - AccessControl
/// - PoolLaunchPad
/// - MasterControl (deployed via CREATE2 with HookMiner to get a special address)
///
/// The PoolManager address is read from the environment variable MANAGER (vm.envAddress).
/// This script writes `script/core-deploy.json` containing the deployed core addresses.
contract DeployCore is Script {
    function run() external returns (address[] memory) {
        vm.startBroadcast();

        address mgr = vm.envAddress("MANAGER");
        require(mgr != address(0), "MANAGER env not set");

        // 1) AccessControl + PoolLaunchPad
        AccessControl accessControl = new AccessControl();
        PoolLaunchPad poolLaunchPad = new PoolLaunchPad(IPoolManager(mgr), accessControl);

        // 2) Deploy MasterControl using the same CREATE2 helper logic as Deploy.s.sol
        MasterControl masterControl = _deployMasterControl(IPoolManager(mgr), accessControl);

        // Configure access control -> pool launchpad so launchpad can register initial pool admins
        accessControl.setPoolLaunchPad(address(poolLaunchPad));

        // Build minimal JSON and write to disk
        bytes memory jb = abi.encodePacked("{");
        jb = abi.encodePacked(jb, '"PoolManager":"', toHexString(mgr), '"');
        jb = abi.encodePacked(jb, ',"AccessControl":"', toHexString(address(accessControl)), '"');
        jb = abi.encodePacked(jb, ',"PoolLaunchPad":"', toHexString(address(poolLaunchPad)), '"');
        jb = abi.encodePacked(jb, ',"MasterControl":"', toHexString(address(masterControl)), '"');
        jb = abi.encodePacked(jb, "}");
        string memory json = string(jb);

        // Print JSON for subsequent scripts (vm.writeFile is not allowed in some environments)
        // Keep output on stdout so external helpers can capture it.
        console.log(json);

        vm.stopBroadcast();

        address[] memory addrs = new address[](4);
        addrs[0] = mgr;
        addrs[1] = address(accessControl);
        addrs[2] = address(poolLaunchPad);
        addrs[3] = address(masterControl);
        return addrs;
    }

    /* ========== Internal helpers (copied logic from Deploy.s.sol) ========== */

    function _deployMasterControl(IPoolManager _manager, AccessControl _accessControl) internal returns (MasterControl) {
        bytes memory ctorArgs = abi.encode(_manager);
        bytes memory creation = type(MasterControl).creationCode;
 
        // Deploy a tiny Create2Factory which will perform the CREATE2 from its address.
        Create2Factory cf = new Create2Factory();
        address deployer = address(cf);
 
        // Find a salt such that CREATE2(deployer, salt, creationWithArgs) yields an address with the hook flags.
        (address predicted, bytes32 salt) = HookMiner.find(deployer, uint160(Hooks.ALL_HOOK_MASK), creation, ctorArgs);
 
        bytes memory creationWithArgs = abi.encodePacked(creation, ctorArgs);
 
        // Use the factory to perform the CREATE2 deployment (factory will deploy with its own address as deployer).
        // Perform the setAccessControl as a separate exec call so it's not bundled into deployAndCall.
        bytes memory setAclData = abi.encodeWithSignature("setAccessControl(address)", address(_accessControl));
        address masterAddr = cf.deploy(creationWithArgs, salt);
        require(masterAddr != address(0), "MasterControl: CREATE2 failed");
        require(masterAddr == predicted, "MasterControl: address mismatch");
 
        (bool ok, ) = cf.exec(masterAddr, setAclData);
        require(ok, "Create2Factory: exec setAccessControl failed");
 
        return MasterControl(masterAddr);
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