// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal CREATE2 deployer used by scripts/tests to perform deterministic deployments.
/// The deployer exposes functions to perform CREATE2 and then optionally execute calls from the deployer context.
contract Create2Factory {
    event Deployed(address indexed addr, bytes32 indexed salt);

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
        emit Deployed(addr, salt);
    }

    /// @notice Deploy `bytecode` using CREATE2 with `salt`, then immediately call `target` with `data` using this contract as msg.sender.
    /// Useful to perform owner-only initializations on the deployed contract.
    function deployAndCall(bytes memory bytecode, bytes32 salt, address target, bytes calldata data) external returns (address addr, bytes memory ret) {
        addr = deploy(bytecode, salt);
        (bool ok, bytes memory r) = target.call(data);
        require(ok, "Create2Factory: init call failed");
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
