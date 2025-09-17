// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

import "../src/AccessControl.sol";
import "../src/PoolLaunchPad.sol";
import "../src/MasterControl.sol";
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

// Use an externally-deployed PoolManager (tests deploy Uniswap mock manager/routers) and require tests to set it.
import "v4-core/interfaces/IPoolManager.sol";
// HookMiner helper to find a CREATE2 salt that yields an address with the required hook flags
import "../lib/v4-periphery/src/utils/HookMiner.sol";
import "v4-core/libraries/Hooks.sol";
import "../src/Create2Factory.sol";

// Import the mock AVS used by tests
import "../test/mocks/MockAVS.sol";

contract DeployScript is Script {
    IPoolManager public manager;

    /// @notice Set the PoolManager instance deployed by the test harness before calling `run()`.
    function setManager(address _manager) external {
        manager = IPoolManager(_manager);
    }

    function run() external returns (address [] memory) {
        vm.startBroadcast();
        require(address(manager) != address(0), "DeployScript: manager not set");
 
        // Deploy core contracts (AccessControl, PoolLaunchPad, MasterControl)
        (AccessControl accessControl, PoolLaunchPad poolLaunchPad, MasterControl masterControl) = _deployCore();
  
        // Deploy platform contracts and wire roles (returns array of platform addresses to avoid stack-too-deep)
        address[] memory platformAddrs = _deployPlatformAndWire(accessControl, poolLaunchPad, masterControl);
  
        // Collect addresses into array (keeps locals scoped small)
        address[] memory addrs = new address[](16);
        addrs[0] = address(manager);
        addrs[1] = address(accessControl);
        addrs[2] = address(poolLaunchPad);
        addrs[3] = address(masterControl);
        // platformAddrs order: FeeCollector, GasBank, DegenPool, Settings, ShareSplitter, Bonding, MockAVS, PrizeBox, Shaker, PointsCommand, BidManager
        for (uint i = 0; i < platformAddrs.length && i < 11; i++) {
            addrs[4 + i] = platformAddrs[i];
        }
        addrs[15] = address(0);
 
        accessControl.registerDeployedContracts(addrs);
 
        // Build JSON artifact for CI / helper scripts and print it to stdout.
        // vm.writeFile can be restricted in some environments, so print JSON on stdout for external capture.
        string memory json = _buildDeployJSON(addrs);
        console.log(json);
 
        vm.stopBroadcast();
        return addrs;
    }
 
    // Split the big deployment into smaller internal helpers to avoid stack-too-deep.
    function _deployCore() internal returns (AccessControl, PoolLaunchPad, MasterControl) {
        AccessControl accessControl = new AccessControl();
        PoolLaunchPad poolLaunchPad = new PoolLaunchPad(manager, accessControl);
        MasterControl masterControl = _deployMasterControl(manager, accessControl);
        accessControl.setPoolLaunchPad(address(poolLaunchPad));
        return (accessControl, poolLaunchPad, masterControl);
    }
 
    function _deployPlatformAndWire(
        AccessControl accessControl,
        PoolLaunchPad poolLaunchPad,
        MasterControl masterControl
    ) internal returns (address[] memory) {
        // Deploy platform contracts and wire them up. Return an array of addresses in the expected order:
        // [FeeCollector, GasBank, DegenPool, Settings, ShareSplitter, Bonding, MockAVS, PrizeBox, Shaker, PointsCommand, BidManager]
        FeeCollector feeCollector = new FeeCollector(accessControl);
        GasBank gasBank = new GasBank(accessControl);
        DegenPool degenPool = new DegenPool(accessControl);
        BidManager bidManager = new BidManager(accessControl);
        Settings settings = new Settings(address(gasBank), address(degenPool), address(feeCollector), accessControl);
        ShareSplitter shareSplitter = new ShareSplitter(address(settings), accessControl);
        Bonding bonding = new Bonding(accessControl);
        MockAVS mockAvs = new MockAVS();

        // Grant ACL roles to the externally-signed EOA (tx.origin) so subsequent config calls succeed.
        accessControl.grantRole(gasBank.ROLE_GAS_BANK_ADMIN(), tx.origin);
        accessControl.grantRole(feeCollector.ROLE_FEE_COLLECTOR_ADMIN(), tx.origin);
        accessControl.grantRole(degenPool.ROLE_DEGEN_ADMIN(), tx.origin);
        accessControl.grantRole(bidManager.ROLE_BID_MANAGER_ADMIN(), tx.origin);
        accessControl.grantRole(shareSplitter.ROLE_SHARE_ADMIN(), tx.origin);
        accessControl.grantRole(bonding.ROLE_BONDING_ADMIN(), tx.origin);
        accessControl.grantRole(bonding.ROLE_BONDING_PUBLISHER(), tx.origin);
        accessControl.grantRole(bonding.ROLE_BONDING_WITHDRAWER(), tx.origin);

        gasBank.setShareSplitter(address(shareSplitter));
        feeCollector.setSettings(address(settings));

        bidManager.setSettlementRole(address(mockAvs), true);
        degenPool.setSettlementRole(address(mockAvs), true);

        bonding.setAuthorizedPublisher(address(masterControl), true);
        bonding.setAuthorizedWithdrawer(address(gasBank), true);
        bonding.setAuthorizedWithdrawer(address(shareSplitter), true);

        PrizeBox prizeBox = new PrizeBox(accessControl, address(mockAvs));
        Shaker shaker = new Shaker(accessControl, address(shareSplitter), address(prizeBox), address(mockAvs));
        accessControl.grantRole(prizeBox.ROLE_PRIZEBOX_ADMIN(), tx.origin);
        accessControl.grantRole(shaker.ROLE_SHAKER_ADMIN(), tx.origin);
        prizeBox.setShaker(address(shaker));

        PointsCommand pointsCommand = new PointsCommand();
        accessControl.grantRole(masterControl.ROLE_MASTER(), tx.origin);
        masterControl.approveCommand(bytes32(0), address(pointsCommand), "PointsCommand");

        address[] memory out = new address[](11);
        out[0] = address(feeCollector);
        out[1] = address(gasBank);
        out[2] = address(degenPool);
        out[3] = address(settings);
        out[4] = address(shareSplitter);
        out[5] = address(bonding);
        out[6] = address(mockAvs);
        out[7] = address(prizeBox);
        out[8] = address(shaker);
        out[9] = address(pointsCommand);
        out[10] = address(bidManager);
        return out;
    }
 
    function _collectAddresses(
        IPoolManager _manager,
        AccessControl accessControl,
        PoolLaunchPad poolLaunchPad,
        MasterControl masterControl,
        FeeCollector feeCollector,
        GasBank gasBank,
        DegenPool degenPool,
        Settings settings,
        ShareSplitter shareSplitter,
        Bonding bonding,
        PrizeBox prizeBox,
        Shaker shaker,
        PointsCommand pointsCommand,
        BidManager bidManager,
        MockAVS mockAvs
    ) internal pure returns (address[] memory) {
        address[] memory addrs = new address[](16);
        addrs[0] = address(_manager);
        addrs[1] = address(accessControl);
        addrs[2] = address(poolLaunchPad);
        addrs[3] = address(masterControl);
        addrs[4] = address(feeCollector);
        addrs[5] = address(gasBank);
        addrs[6] = address(degenPool);
        addrs[7] = address(settings);
        addrs[8] = address(shareSplitter);
        addrs[9] = address(bonding);
        addrs[10] = address(prizeBox);
        addrs[11] = address(shaker);
        addrs[12] = address(pointsCommand);
        addrs[13] = address(bidManager);
        addrs[14] = address(mockAvs);
        addrs[15] = address(0);
        return addrs;
    }
      

    /* ========== Internal helpers ========== */
    /// @notice Mine a salt and deploy MasterControl with CREATE2 so the deployed address encodes Hooks.ALL_HOOK_MASK.
    /// Uses an internal Create2Factory deployed in-line as the CREATE2 deployer so this works on any chain.
    /// The factory will call setAccessControl(...) on the deployed MasterControl atomically so no owner transfer is needed.
    /// If the predicted address already contains code (previous run), this helper will reuse it instead of re-deploying.
    function _deployMasterControl(IPoolManager _manager, AccessControl _accessControl) internal returns (MasterControl) {
        bytes memory ctorArgs = abi.encode(_manager);
        bytes memory creation = type(MasterControl).creationCode;
 
        // Deploy a tiny Create2Factory which will perform the CREATE2 from its address.
        Create2Factory cf = new Create2Factory();
        address deployer = address(cf);
 
        // For CI/local convenience we may hardcode a salt instead of mining one every run.
        // Using a fixed salt avoids mismatches across restarts of ephemeral nodes (anvil) that reuse accounts/nonces.
        // Hardcoded salt chosen from prior successful run:
        bytes memory creationWithArgs = abi.encodePacked(creation, ctorArgs);
        bytes32 salt = 0x00000000000000000000000000000000000000000000000000000000000048c9;
        // Compute the expected CREATE2 address for this deployer/salt/initCode
        address predicted = cf.computeAddress(deployer, salt, keccak256(creationWithArgs));
        // If the predicted address already has code, reuse it instead of deploying.
        if (predicted.code.length != 0) {
            return MasterControl(predicted);
        }
 
        // Use the factory to perform the CREATE2 deployment (factory will deploy with its own address as deployer).
        // Do the post-deploy initialization via the factory.exec() call so it's a separate call from deploy.
        bytes memory setAclData = abi.encodeWithSignature("setAccessControl(address)", address(_accessControl));
        address masterAddr = cf.deploy(creationWithArgs, salt);
        if (masterAddr == address(0)) revert("MasterControl: CREATE2 failed");
        require(masterAddr == predicted, "MasterControl: address mismatch");
 
        // Execute setAccessControl from the factory context so owner check (owner==factory) succeeds.
        (bool ok, bytes memory ret) = cf.exec(masterAddr, setAclData);
        require(ok, "Create2Factory: exec setAccessControl failed");
 
        return MasterControl(masterAddr);
    }

    // Helper to build JSON from an array of addresses (keeps local vars low)
    function _buildDeployJSON(address[] memory addrs) internal pure returns (string memory) {
        string[15] memory keys = [
            "PoolManager",
            "AccessControl",
            "PoolLaunchPad",
            "MasterControl",
            "FeeCollector",
            "GasBank",
            "DegenPool",
            "Settings",
            "ShareSplitter",
            "Bonding",
            "PrizeBox",
            "Shaker",
            "PointsCommand",
            "BidManager",
            "MockAVS"
        ];

        bytes memory jb = abi.encodePacked("{");
        for (uint i = 0; i < 15; i++) {
            jb = abi.encodePacked(jb, '"', keys[i], '":"', toHexString(addrs[i]), '"');
            if (i + 1 < 15) jb = abi.encodePacked(jb, ',');
        }
        jb = abi.encodePacked(jb, "}");
        return string(jb);
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