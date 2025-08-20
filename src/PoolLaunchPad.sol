// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Currency} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

/// @notice Small deployer that mints an OpenZeppelin ERC20 to a chosen recipient.
 contract ERC20Deployer is ERC20 {
    constructor(string memory name_, string memory symbol_, address initialHolder, uint256 initialSupply)
        ERC20(name_, symbol_)
    {
        _mint(initialHolder, initialSupply);
    }
}


/// @title PoolLaunchPad
/// @notice Helper to create ERC20 tokens (using OpenZeppelin) and initialize Uniswap v4 pools.
/// @dev This contract focuses on token creation and pool initialization only (LP seeding removed).
contract PoolLaunchPad {
    IPoolManager public immutable manager;

    event TokenCreated(address indexed creator, address token);
    event PoolInitialized(address indexed creator, PoolId poolId);

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    /// @notice Create a full ERC20 (OpenZeppelin) and mint the initial supply to this contract (used to seed pools).
    /// @dev Returns the created token address.
    function createTokenFull(string calldata name, string calldata symbol, uint256 supply)
        public
        returns (address)
    {
        ERC20Deployer token = new ERC20Deployer(name, symbol, address(this), supply);
        emit TokenCreated(msg.sender, address(token));
        return address(token);
    }

    /// @notice Convenience functions to create tokens and initialize pools for common pair configurations:
    ///         - new token paired with native ETH
    ///         - supplied token paired with native ETH
    ///         - new token paired with supplied ERC20
    ///         - supplied ERC20 pair
    /// @dev Call the specific function that matches the desired token/native combination.
    /// @notice Create a new ERC20 token and initialize a pool where the token is currency0 and the other side is native ETH.
    function createNewTokenAndInitWithNative(
        string calldata tokenName,
        string calldata tokenSymbol,
        uint256 tokenSupply,
        uint24 fee,
        int24 tickSpacing,
        uint160 sqrtPriceX96,
        IHooks hooks
    ) external returns (PoolId poolId, address tokenAddr) {
        tokenAddr = createTokenFull(tokenName, tokenSymbol, tokenSupply);
        address currency0Addr = tokenAddr;
        address currency1Addr = address(0);
        (address c0, address c1) = _orderTokens(currency0Addr, currency1Addr);
        PoolKey memory key = _buildPoolKey(c0, c1, fee, tickSpacing, hooks);
        poolId = key.toId();
        _initializePool(key, sqrtPriceX96);
        return (poolId, tokenAddr);
    }

    /// @notice Initialize a pool pairing a supplied ERC20 (as currency0) with native ETH (currency1).
    function createSuppliedTokenAndInitWithNative(
        address existingTokenAddr,
        uint24 fee,
        int24 tickSpacing,
        uint160 sqrtPriceX96,
        IHooks hooks
    ) external returns (PoolId poolId, address tokenAddr) {
        require(existingTokenAddr != address(0), "existing token required");
        tokenAddr = existingTokenAddr;
        address currency0Addr = address(0);
        address currency1Addr = tokenAddr;
        (address c0, address c1) = _orderTokens(currency0Addr, currency1Addr);
        PoolKey memory key = _buildPoolKey(c0, c1, fee, tickSpacing, hooks);
        poolId = key.toId();
        _initializePool(key, sqrtPriceX96);
        return (poolId, tokenAddr);
    }

    /// @notice Create a new ERC20 token and initialize a pool pairing it with a supplied ERC20 (token is currency0).
    function createNewTokenAndInitWithToken(
        string calldata tokenName,
        string calldata tokenSymbol,
        uint256 tokenSupply,
        address otherTokenAddr,
        uint24 fee,
        int24 tickSpacing,
        uint160 sqrtPriceX96,
        IHooks hooks
    ) external returns (PoolId poolId, address tokenAddr) {
        require(otherTokenAddr != address(0), "other token required");
        tokenAddr = createTokenFull(tokenName, tokenSymbol, tokenSupply);
        address currency0Addr = tokenAddr;
        address currency1Addr = otherTokenAddr;
        (address c0, address c1) = _orderTokens(currency0Addr, currency1Addr);
        PoolKey memory key = _buildPoolKey(c0, c1, fee, tickSpacing, hooks);
        poolId = key.toId();
        _initializePool(key, sqrtPriceX96);
        return (poolId, tokenAddr);
    }

    /// @notice Initialize a pool using two supplied ERC20 tokens (tokenA as currency0, tokenB as currency1).
    function initWithSuppliedTokens(
        address tokenA,
        address tokenB,
        uint24 fee,
        int24 tickSpacing,
        uint160 sqrtPriceX96,
        IHooks hooks
    ) external returns (PoolId poolId) {
        require(tokenA != address(0) && tokenB != address(0), "both tokens required");
        address currency0Addr = tokenA;
        address currency1Addr = tokenB;
        (address c0, address c1) = _orderTokens(currency0Addr, currency1Addr);
        PoolKey memory key = _buildPoolKey(c0, c1, fee, tickSpacing, hooks);
        poolId = key.toId();
        _initializePool(key, sqrtPriceX96);
        return poolId;
    }

    // LP seeding logic removed: this contract now focuses on token creation and pool initialization only.

    /* ========== Internal helpers to reduce stack usage ========== */

    function _ensureToken(
        bool createNewToken,
        string calldata tokenName,
        string calldata tokenSymbol,
        uint256 tokenSupply,
        address existingTokenAddr
    ) internal returns (address tokenAddr) {
        if (createNewToken) {
            tokenAddr = createTokenFull(tokenName, tokenSymbol, tokenSupply);
        } else {
            tokenAddr = existingTokenAddr;
            require(tokenAddr != address(0), "existing token required");
        }
    }

    function _buildPoolKey(
        address currency0Addr,
        address currency1Addr,
        uint24 fee,
        int24 tickSpacing,
        IHooks hooks
    ) internal pure returns (PoolKey memory) {
        Currency c0 = Currency.wrap(currency0Addr);
        Currency c1 = Currency.wrap(currency1Addr);
        return PoolKey(c0, c1, fee, tickSpacing, hooks);
    }

    /// @notice Order two token addresses such that the lower-address token becomes currency0.
    /// @dev This ensures PoolKey creation follows the canonical ordering (token0 < token1).
    function _orderTokens(address a, address b) internal pure returns (address c0, address c1) {
        if (a == b) return (a, b);
        return a < b ? (a, b) : (b, a);
    }

    function _initializePool(PoolKey memory key, uint160 sqrtPriceX96) internal {
        PoolId id = key.toId();
        manager.initialize(key, sqrtPriceX96);
        emit PoolInitialized(msg.sender, id);
    }


    // Allow contract to receive ETH when seeding native pairs
    receive() external payable {}
}