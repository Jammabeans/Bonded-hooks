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

        // 2) Core wiring contracts
        AccessControl accessControl = new AccessControl();
        PoolLaunchPad poolLaunchPad = new PoolLaunchPad(manager, accessControl);

        // 3) Deploy MasterControl using helper that mines a salt and performs CREATE2 so its address encodes ALL_HOOK_MASK
        // Pass accessControl into the helper so the Create2Factory can set it atomically during deployment.
        MasterControl masterControl = _deployMasterControl(manager, accessControl);
 
        // Configure access control -> pool launchpad so launchpad can register initial pool admins
        accessControl.setPoolLaunchPad(address(poolLaunchPad));

        // 4) Deploy platform utility contracts (pass AccessControl so contracts use ACL)
        FeeCollector feeCollector = new FeeCollector(accessControl);
        GasBank gasBank = new GasBank(accessControl);
        DegenPool degenPool = new DegenPool(accessControl);
 
        // 5) BidManager (deploy early so AVS can interact)
        BidManager bidManager = new BidManager(accessControl);
 
        // 6) Settings requires gasBank, degenPool, feeCollector and AccessControl
        Settings settings = new Settings(address(gasBank), address(degenPool), address(feeCollector), accessControl);
 
        // 7) ShareSplitter uses Settings and AccessControl
        ShareSplitter shareSplitter = new ShareSplitter(address(settings), accessControl);
 
        // 8) Bonding (use AccessControl)
        Bonding bonding = new Bonding(accessControl);

        // 9) Deploy MockAVS (tests rely on AVS behavior beyond PrizeBox/Shaker)
        MockAVS mockAvs = new MockAVS();

        // 10) Wire GasBank / FeeCollector / ShareSplitter / Bonding
        // Grant the ACL roles to the externally-signed EOA (the broadcast sender) so subsequent config calls succeed.
        accessControl.grantRole(gasBank.ROLE_GAS_BANK_ADMIN(), tx.origin);
        accessControl.grantRole(feeCollector.ROLE_FEE_COLLECTOR_ADMIN(), tx.origin);
        accessControl.grantRole(degenPool.ROLE_DEGEN_ADMIN(), tx.origin);
        accessControl.grantRole(bidManager.ROLE_BID_MANAGER_ADMIN(), tx.origin);
        accessControl.grantRole(shareSplitter.ROLE_SHARE_ADMIN(), tx.origin);
        // Bonding needs admin/publisher/withdrawer roles so DeployScript (EOA) can configure and initialize Bonding.
        accessControl.grantRole(bonding.ROLE_BONDING_ADMIN(), tx.origin);
        accessControl.grantRole(bonding.ROLE_BONDING_PUBLISHER(), tx.origin);
        accessControl.grantRole(bonding.ROLE_BONDING_WITHDRAWER(), tx.origin);
 
        gasBank.setShareSplitter(address(shareSplitter));
        feeCollector.setSettings(address(settings));
 
        // Grant settlement roles to MockAVS so it can call BidManager/DegenPool operations
        bidManager.setSettlementRole(address(mockAvs), true);
        degenPool.setSettlementRole(address(mockAvs), true);
 
        // Configure Bonding permissions (deployer is owner)
        bonding.setAuthorizedPublisher(address(masterControl), true);
        bonding.setAuthorizedWithdrawer(address(gasBank), true);
        bonding.setAuthorizedWithdrawer(address(shareSplitter), true);

        // 11) PrizeBox & Shaker (pass mockAvs as the AVS address) and include AccessControl
        PrizeBox prizeBox = new PrizeBox(accessControl, address(mockAvs));
        Shaker shaker = new Shaker(accessControl, address(shareSplitter), address(prizeBox), address(mockAvs));
        // Grant PrizeBox/Shaker admin roles to the broadcast EOA (tx.origin) so setup calls succeed.
        accessControl.grantRole(prizeBox.ROLE_PRIZEBOX_ADMIN(), tx.origin);
        accessControl.grantRole(shaker.ROLE_SHAKER_ADMIN(), tx.origin);
        // ensure PrizeBox knows the Shaker
        prizeBox.setShaker(address(shaker));

        // 12) PointsCommand (delegatecall target)
        PointsCommand pointsCommand = new PointsCommand();
        // Ensure the broadcast EOA holds ROLE_MASTER so master-level setup calls succeed in this run.
        accessControl.grantRole(masterControl.ROLE_MASTER(), tx.origin);
        // Approve the command for a representative hookPath (tests will compute actual hookPaths per-pool).
        masterControl.approveCommand(bytes32(0), address(pointsCommand), "PointsCommand");

        

        // Build JSON artifact via helper to avoid "stack too deep"
        address[] memory addrs = new address[](16);
        addrs[0] = address(manager);
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
        // reserved slot
        addrs[15] = address(0);

        accessControl.registerDeployedContracts(addrs);

        vm.stopBroadcast();

        return addrs;
    }

    

    /* ========== Internal helpers ========== */
    /// @notice Mine a salt and deploy MasterControl with CREATE2 so the deployed address encodes Hooks.ALL_HOOK_MASK.
    /// Uses an internal Create2Factory deployed in-line as the CREATE2 deployer so this works on any chain.
    /// The factory will call setAccessControl(...) on the deployed MasterControl atomically so no owner transfer is needed.
    function _deployMasterControl(IPoolManager _manager, AccessControl _accessControl) internal returns (MasterControl) {
        bytes memory ctorArgs = abi.encode(_manager);
        bytes memory creation = type(MasterControl).creationCode;
 
        // Deploy a tiny Create2Factory which will perform the CREATE2 from its address.
        Create2Factory cf = new Create2Factory();
        address deployer = address(cf);
 
        // Find a salt such that CREATE2(deployer, salt, creationWithArgs) yields an address with the hook flags.
        (address predicted, bytes32 salt) = HookMiner.find(deployer, uint160(Hooks.ALL_HOOK_MASK), creation, ctorArgs);
 
        bytes memory creationWithArgs = abi.encodePacked(creation, ctorArgs);
 
        // Use the factory to perform the CREATE2 deployment (factory will deploy with its own address as deployer),
        // and have the factory immediately call setAccessControl on the deployed MasterControl so no ownership transfer is required.
        bytes memory setAclData = abi.encodeWithSignature("setAccessControl(address)", address(_accessControl));
        (address masterAddr, bytes memory ret) = cf.deployAndCall(creationWithArgs, salt, predicted, setAclData);
 
        require(masterAddr != address(0), "MasterControl: CREATE2 failed");
        require(masterAddr == predicted, "MasterControl: address mismatch");
 
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