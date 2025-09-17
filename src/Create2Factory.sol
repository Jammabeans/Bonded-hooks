// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal CREATE2 deployer used by scripts/tests to perform deterministic deployments.
/// The deployer exposes functions to perform CREATE2 and then optionally execute calls from the deployer context.
contract Create2Factory {
    event Deployed(address indexed addr, bytes32 indexed salt);
    /// Emitted with the runtime code size of the deployed contract (helps diagnose Create2 failures).
    event DeployedWithCode(address indexed addr, bytes32 indexed salt, uint256 codeSize);

    /// @notice Deploy `bytecode` using CREATE2 with `salt`.
    /// @param bytecode Creation code (including constructor args) to deploy.
    /// @param salt Salt value used for CREATE2.
    /// @return addr The deployed address.
    function deploy(bytes memory bytecode, bytes32 salt) public returns (address addr) {
        require(bytecode.length != 0, "Create2Factory: empty bytecode");
        assembly {
            addr := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }
        require(addr != address(0), "Create2Factory: create2 failed");

        // Query code size to help diagnose EIP-170 / contract-size issues.
        uint256 size;
        assembly { size := extcodesize(addr) }

        emit Deployed(addr, salt);
        emit DeployedWithCode(addr, salt, size);
    }

    /// @notice Deploy `bytecode` using CREATE2 with `salt`, then immediately call the deployed contract with `data`
    /// using this contract as msg.sender. `expected` may be provided (predicted address) for sanity-checks;
    /// if non-zero it's validated against the actual deployed address.
    function deployAndCall(bytes memory bytecode, bytes32 salt, address expected, bytes calldata data) external returns (address addr, bytes memory ret) {
        addr = deploy(bytecode, salt);

        // Call the actual deployed address (safer than calling a predicted address supplied by the caller).
        (bool ok, bytes memory r) = addr.call(data);

        // If the init call failed, bubble up the revert reason when present so callers see the exact revert.
        if (!ok) {
            if (r.length > 0) {
                assembly {
                    revert(add(r, 32), mload(r))
                }
            }
            revert("Create2Factory: init call failed");
        }

        // If the caller provided an expected (predicted) address, sanity-check it matches the deployed addr.
        if (expected != address(0) && expected != addr) {
            revert("Create2Factory: address mismatch");
        }

        ret = r;
    }

    /// @notice Execute an arbitrary call from this contract to `target`. Caller can use this to perform owner-only setup if this contract is owner.
    function exec(address target, bytes calldata data) external returns (bool ok, bytes memory ret) {
        (ok, ret) = target.call(data);
    }

    /// @notice Compute the CREATE2 address for given parameters.
    function computeAddress(address deployer, bytes32 salt, bytes32 initCodeHash) external pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, initCodeHash)))));
    }
}
