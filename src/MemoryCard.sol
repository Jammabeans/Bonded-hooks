// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// --- Uniswap V4 Periphery Imports ---
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {console} from "forge-std/console.sol";

// MemoryCard: A utility contract for storing and reading arbitrary data (not a Uniswap hook)

contract MemoryCard {

    // storage for deployed contract addresses per user
    mapping(address => address) private store2;

    // constants for contract creation prefix and length
    uint256 constant CREATION_PREFIX_INT = 0x60ff600d60003960ff6000f30000000000000000000000000000000000000000;
    uint8 constant CREATION_PREFIX_LEN = 13;

    // Simple key-value store: user => key => value
    mapping(address => mapping(bytes32 => bytes)) private store;

    // Alternative store for method 2: mapping to deployed contract addresses
    //mapping(address => mapping(bytes32 => address)) private store2;

    // Store arbitrary data under a key for the sender (method 1)
    function write(bytes32 key, bytes calldata value) external {
        store[msg.sender][key] = value;
        console.log("MemoryCard / Write / key: ");
        console.logBytes32( key);
        console.logBytes(value);
        console.log("MemoryCard / Write / msg.sender : ", msg.sender);
    }

    // Read data for a user/key (method 1)
    function read(address user, bytes32 key) external view returns (bytes memory) {
        return store[user][key];
        console.log("MemoryCard / Read / key: ");
        console.logBytes32(key);
        console.log("MemoryCard / Read / user: ", user);
        console.log("MemoryCard / Read / value: ");
        console.logBytes(store[user][key]);
    }

    // Convenience: clear a key for the sender (method 1)
    function clear(bytes32 key) external {
        delete store[msg.sender][key];
    }

    // Creation code prefix for returning N bytes from offset 0x0f (15)
    // Must be exactly 13 bytes for patching logic
    // Must be exactly 13 bytes for patching logic
    // Must be exactly 13 bytes for patching logic
    
function saveToRom(bytes calldata value) external {
    require(value.length <= 0xff, "Value too long");

    bytes memory creationCode = new bytes(CREATION_PREFIX_LEN + value.length);

    assembly {
        // store creation prefix (13 bytes padded)
        mstore(add(creationCode, 0x20), CREATION_PREFIX_INT)
        mstore8(add(creationCode, 0x21), value.length)
        mstore8(add(creationCode, 0x28), value.length)

        // copy value from calldata to creationCode buffer
        let src := add(value.offset, 0x20)
        let dest := add(add(creationCode, 0x20), CREATION_PREFIX_LEN)
        let len := value.length
        let fullWords := div(len, 32)
        let remainder := mod(len, 32)

        // copy full 32-byte words
        for { let i := 0 } lt(i, fullWords) { i := add(i, 1) } {
            mstore(add(dest, mul(i, 32)), calldataload(add(src, mul(i, 32))))
        }

        // copy last partial word if any
        if gt(remainder, 0) {
            let mask := sub(shl(mul(sub(32, remainder), 8), 1), 1)
            let lastWord := calldataload(add(src, mul(fullWords, 32)))
            lastWord := and(lastWord, not(mask))
            mstore(add(dest, mul(fullWords, 32)), lastWord)
        }
    }

    // Deploy the contract with create and get deployed address
    address deployed;
    assembly {
        let dataPtr := add(creationCode, 0x20)
        let len := mload(creationCode)
        deployed := create(0, dataPtr, len)
    }
    require(deployed != address(0), "Deployment failed");

    // Save deployed address mapped to sender, overwriting previous if any
    store2[msg.sender] = deployed;
}

function readFromRom(address user) external view returns (bytes memory) {
    address deployed = store2[user];
    require(deployed != address(0), "No contract stored");

    uint256 size;
    assembly {
        size := extcodesize(deployed)
    }
    bytes memory code = new bytes(size);
    assembly {
        extcodecopy(deployed, add(code, 0x20), 0, size)
    }
    return code;
}

    // Convenience: clear a key for the sender (method 2)
    function store2clear() external {
        delete store2[msg.sender];
    }
}