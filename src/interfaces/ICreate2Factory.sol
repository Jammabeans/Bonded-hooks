// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ICreate2Factory
/// @notice Interface for the minimal CREATE2 deployer used by scripts/tests.
interface ICreate2Factory {
    event Deployed(address indexed addr, bytes32 indexed salt);

    function deploy(bytes memory bytecode, bytes32 salt) external returns (address addr);
    function deployAndCall(bytes memory bytecode, bytes32 salt, address target, bytes calldata data) external returns (address addr, bytes memory ret);
    function exec(address target, bytes calldata data) external returns (bool ok, bytes memory ret);
    function computeAddress(address deployer, bytes32 salt, bytes32 initCodeHash) external pure returns (address);
}