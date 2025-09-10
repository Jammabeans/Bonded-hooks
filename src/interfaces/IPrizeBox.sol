// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IBurnable} from "./MocksAndInterfaces.sol";

/// @title IPrizeBox
/// @notice Interface for the PrizeBox ERC721 vault.
interface IPrizeBox {
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);
    event AVSSet(address indexed avs);
    event BoxCreated(uint256 indexed boxId, address indexed owner);
    event ETHDeposited(uint256 indexed boxId, uint256 amount);
    event ERC20Deposited(uint256 indexed boxId, address indexed token, uint256 amount);
    event SharesRegistered(uint256 indexed boxId, address indexed token, uint256 amount);
    event BoxOpened(uint256 indexed boxId, address indexed opener);
    event SharesBurned(uint256 indexed boxId, address indexed token, uint256 amount);

    // ERC721 minimal
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function ownerOf(uint256 tokenId) external view returns (address);
    function balanceOf(address who) external view returns (uint256);

    // Admin
    function transferOwnership(address newOwner) external;
    function setAVS(address _avs) external;
    function setShaker(address _shaker) external;

    // AVS actions
    function createBox(address boxOwner) external returns (uint256);
    function awardBoxTo(uint256 boxId, address to) external;

    // Deposits / register shares
    function depositToBox(uint256 boxId) external payable;
    function depositToBoxERC20(uint256 boxId, address token, uint256 amount) external;
    function registerShareTokens(uint256 boxId, address token, uint256 amount) external;

    // Owner/utility
    function openBox(uint256 boxId) external;
}