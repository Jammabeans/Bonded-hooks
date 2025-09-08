// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {AccessControl} from "./AccessControl.sol";
import "./Settings.sol";

/// @title ShareSplitter
/// @notice Splits incoming ETH according to per-sender or default shares from Settings and forwards to recipients.
contract ShareSplitter {
    event SplitExecuted(address indexed sender, uint256 amount, address[] recipients, uint256[] amounts);

    Settings public settings;

    // Legacy owner (deployer) retained for backward compatibility; prefer role-based checks via AccessControl.
    address public owner;
    AccessControl public accessControl;
    bytes32 public constant ROLE_SHARE_ADMIN = keccak256("ROLE_SHARE_ADMIN");

    constructor(address settingsAddr, AccessControl _accessControl) {
        require(settingsAddr != address(0), "Zero settings");
        settings = Settings(settingsAddr);
        owner = msg.sender;
        accessControl = _accessControl;
    }

    receive() external payable {
        _split(msg.sender, msg.value);
    }

    /// @notice Explicit entrypoint to split and forward funds for msg.sender
    function splitAndForward() external payable {
        _split(msg.sender, msg.value);
    }

    function _split(address sender, uint256 amount) internal {
        require(amount > 0, "No ETH");
        (address[] memory recipients, uint256[] memory weights) = settings.getSharesFor(sender);
        require(recipients.length > 0, "No recipients");
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < weights.length; i++) {
            totalWeight += weights[i];
        }
        require(totalWeight > 0, "Zero total weight");

        uint256 distributed = 0;
        uint256[] memory amounts = new uint256[](recipients.length);
        for (uint256 i = 0; i < recipients.length; i++) {
            uint256 share = (amount * weights[i]) / totalWeight;
            amounts[i] = share;
            distributed += share;
            if (share > 0) {
                (bool sent, ) = recipients[i].call{value: share}("");
                require(sent, "Transfer failed");
            }
        }

        // handle remainder due to rounding: send to last recipient
        uint256 remainder = amount - distributed;
        if (remainder > 0) {
            uint256 lastIdx = recipients.length - 1;
            amounts[lastIdx] += remainder;
            (bool sentRem, ) = recipients[lastIdx].call{value: remainder}("");
            require(sentRem, "Remainder transfer failed");
        }

        emit SplitExecuted(sender, amount, recipients, amounts);
    }

    function setSettings(address settingsAddr) external {
        require(_isShareAdmin(msg.sender), "ShareSplitter: not admin");
        require(settingsAddr != address(0), "Zero settings");
        settings = Settings(settingsAddr);
    }

    /// @notice Helper that prefers role-based checks when AccessControl is configured,
    ///         otherwise falls back to legacy owner semantics for compatibility.
    function _isShareAdmin(address user) internal view returns (bool) {
        if (address(accessControl) != address(0)) {
            return accessControl.hasRole(ROLE_SHARE_ADMIN, user);
        }
        return user == owner;
    }
}