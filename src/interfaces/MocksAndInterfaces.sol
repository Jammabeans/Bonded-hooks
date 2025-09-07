// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Collection of interfaces and lightweight mocks used by Shaker/PrizeBox tests.
/// Location: [`Bonded-hooks/src/interfaces/MocksAndInterfaces.sol:1`](Bonded-hooks/src/interfaces/MocksAndInterfaces.sol:1)

interface IShareSplitter {
    /// @notice Receive a split for a given poolId (ETH forwarded)
    function receiveSplit(uint256 poolId) external payable;
}

interface IPrizeBox {
    /// @notice Deposit ETH to a specific box
    function depositToBox(uint256 boxId) external payable;
    function depositToBoxERC20(uint256 boxId, address token, uint256 amount) external;
    function awardBoxTo(uint256 boxId, address to) external;
}

interface IBurnable {
    /// @notice Burn tokens from `account`. Caller must have approval or be authorized by token semantics.
    function burnFrom(address account, uint256 amount) external;
}

/// -----------------------------------------------------------------------------
/// Mocks (lightweight) - useful for unit tests
/// -----------------------------------------------------------------------------
/// MockShareSplitter: records last received splits and total received per pool
contract MockShareSplitter {
    mapping(uint256 => uint256) public receivedPerPool;
    event SplitReceived(uint256 indexed poolId, uint256 amount);

    // This function's selector matches IShareSplitter.receiveSplit(uint256)
    function receiveSplit(uint256 poolId) external payable {
        receivedPerPool[poolId] += msg.value;
        emit SplitReceived(poolId, msg.value);
    }

    // helper to withdraw funds to test harness
    function withdraw(address payable to, uint256 amount) external {
        require(to != address(0), "zero");
        (bool ok, ) = to.call{value: amount}("");
        require(ok, "withdraw failed");
    }

    receive() external payable {}
}

/// Minimal ERC20 with burnFrom and mint for tests
contract MockBurnableERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Burned(address indexed from, uint256 amount);

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) external {
        require(to != address(0), "mint zero");
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (msg.sender != from && allowed != type(uint256).max) {
            require(allowed >= amount, "insufficient allowance");
            allowance[from][msg.sender] = allowed - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(balanceOf[from] >= amount, "insufficient balance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }

    /// @notice burnFrom follows ERC20-approach: spender must have allowance or caller == account
    function burnFrom(address account, uint256 amount) external {
        if (msg.sender != account) {
            uint256 allowed = allowance[account][msg.sender];
            require(allowed >= amount, "burnFrom: allowance");
            allowance[account][msg.sender] = allowed - amount;
        }
        require(balanceOf[account] >= amount, "burnFrom: balance");
        balanceOf[account] -= amount;
        totalSupply -= amount;
        emit Burned(account, amount);
        emit Transfer(account, address(0), amount);
    }
}

/// Aliases for clarity in tests
contract MockDegenShare is MockBurnableERC20 {
    constructor() MockBurnableERC20("MockDegenShare", "MDS", 18) {}
}

contract MockBondedShare is MockBurnableERC20 {
    constructor() MockBurnableERC20("MockBondedShare", "MBS", 18) {}
}