// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./Settings.sol";

/// @title ShareSplitter
/// @notice Splits incoming ETH according to per-sender or default shares from Settings and forwards to recipients.
contract ShareSplitter is Ownable {
    event SplitExecuted(address indexed sender, uint256 amount, address[] recipients, uint256[] amounts);

    Settings public settings;

    constructor(address settingsAddr) Ownable(msg.sender) {
        require(settingsAddr != address(0), "Zero settings");
        settings = Settings(settingsAddr);
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

    function setSettings(address settingsAddr) external onlyOwner {
        require(settingsAddr != address(0), "Zero settings");
        settings = Settings(settingsAddr);
    }
}