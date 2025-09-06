// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";

/// @title Settings
/// @notice Stores default and per-sender share splits used by ShareSplitter.
/// Shares are simple (recipient, weight). Owner may update default shares or set per-sender overrides.
contract Settings is Ownable {
    struct Share {
        address recipient;
        uint256 weight;
    }

    // default shares array
    Share[] internal defaultShares;

    // per-sender override shares
    mapping(address => Share[]) internal customShares;
    mapping(address => bool) public hasCustomShares;

    event DefaultSharesUpdated(address[] recipients, uint256[] weights);
    event CustomSharesUpdated(address indexed ownerAddr, address[] recipients, uint256[] weights);

    /// @notice Initialize Settings with deployer as owner and set initial default split.
    /// @param gasBank address for GasBank share
    /// @param degenPool address for DegenPool share
    /// @param feeCollector address for FeeCollector share
    constructor(address gasBank, address degenPool, address feeCollector) Ownable(msg.sender) {
        require(gasBank != address(0) && degenPool != address(0) && feeCollector != address(0), "Zero addr");
        address[] memory recips = new address[](3);
        uint256[] memory weights = new uint256[](3);
        recips[0] = gasBank;
        recips[1] = degenPool;
        recips[2] = feeCollector;
        // default weights per spec: GasBank=400, DegenPool=250, Fees=100
        weights[0] = 400;
        weights[1] = 250;
        weights[2] = 100;
        _setDefaultShares(recips, weights);
    }

    /// @notice Owner can replace the default shares entirely.
    function setDefaultShares(address[] calldata recipients, uint256[] calldata weights) external onlyOwner {
        _setDefaultShares(recipients, weights);
    }

    function _setDefaultShares(address[] memory recipients, uint256[] memory weights) internal {
        require(recipients.length == weights.length, "Mismatched arrays");
        // clear existing
        delete defaultShares;
        uint256 len = recipients.length;
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < len; i++) {
            require(recipients[i] != address(0), "Zero recipient");
            require(weights[i] > 0, "Zero weight");
            defaultShares.push(Share({recipient: recipients[i], weight: weights[i]}));
            totalWeight += weights[i];
        }
        require(totalWeight > 0, "Total weight zero");
        emit DefaultSharesUpdated(recipients, weights);
    }

    /// @notice Owner may set per-sender custom shares (override default).
    function setCustomSharesFor(address ownerAddr, address[] calldata recipients, uint256[] calldata weights) external onlyOwner {
        require(ownerAddr != address(0), "Zero owner");
        _setCustomShares(ownerAddr, recipients, weights);
    }

    function _setCustomShares(address ownerAddr, address[] memory recipients, uint256[] memory weights) internal {
        require(recipients.length == weights.length, "Mismatched arrays");
        delete customShares[ownerAddr];
        uint256 len = recipients.length;
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < len; i++) {
            require(recipients[i] != address(0), "Zero recipient");
            require(weights[i] > 0, "Zero weight");
            customShares[ownerAddr].push(Share({recipient: recipients[i], weight: weights[i]}));
            totalWeight += weights[i];
        }
        require(totalWeight > 0, "Total weight zero");
        hasCustomShares[ownerAddr] = true;
        emit CustomSharesUpdated(ownerAddr, recipients, weights);
    }

    /// @notice Owner may clear custom shares for an address (revert to default)
    function clearCustomSharesFor(address ownerAddr) external onlyOwner {
        delete customShares[ownerAddr];
        hasCustomShares[ownerAddr] = false;
        emit CustomSharesUpdated(ownerAddr, new address[](0), new uint256[](0));
    }

    /// @notice Get the shares (recipients and weights) that apply for a given address. Returns default if no custom override.
    function getSharesFor(address ownerAddr) external view returns (address[] memory recipients, uint256[] memory weights) {
        if (hasCustomShares[ownerAddr]) {
            Share[] storage s = customShares[ownerAddr];
            uint256 len = s.length;
            recipients = new address[](len);
            weights = new uint256[](len);
            for (uint256 i = 0; i < len; i++) {
                recipients[i] = s[i].recipient;
                weights[i] = s[i].weight;
            }
            return (recipients, weights);
        } else {
            uint256 len = defaultShares.length;
            recipients = new address[](len);
            weights = new uint256[](len);
            for (uint256 i = 0; i < len; i++) {
                recipients[i] = defaultShares[i].recipient;
                weights[i] = defaultShares[i].weight;
            }
            return (recipients, weights);
        }
    }

    /// @notice Get default shares explicitly
    function getDefaultShares() external view returns (address[] memory recipients, uint256[] memory weights) {
        uint256 len = defaultShares.length;
        recipients = new address[](len);
        weights = new uint256[](len);
        for (uint256 i = 0; i < len; i++) {
            recipients[i] = defaultShares[i].recipient;
            weights[i] = defaultShares[i].weight;
        }
        return (recipients, weights);
    }
}