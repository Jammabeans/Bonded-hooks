// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Shaker — mini-game coordinator
/// @dev AVS (authorized address) starts rounds by providing a poolId. Ticket pricing is compounded per purchase.
///      When a round finalizes AVS calls finalizeRound which splits funds and deposits prize portions into PrizeBox(s).
interface IShareSplitter {
    function receiveSplit(uint256 poolId) external payable;
}

interface IPrizeBox {
    function depositToBox(uint256 boxId) external payable;
    function depositToBoxERC20(uint256 boxId, address token, uint256 amount) external;
    function awardBoxTo(uint256 boxId, address to) external;
}

contract Shaker {
    uint256 public constant BIPS_DENOM = 10000;

    address public owner;
    address public avs; // authorized AVS address that may start/finalize rounds
    IShareSplitter public shareSplitter;
    IPrizeBox public prizeBoxContract;

    uint256 public nextRoundId;

    // Configurable params
    uint256 public ticketStartPrice = 0.01 ether;
    uint256 public incrementBips = 300; // 3% default
    uint256 public roundDuration = 120; // seconds
    // Splits (in bips)
    uint256 public prizeBoxesBips = 5000; // 50%
    uint256 public lpBips = 3000; // 30%
    uint256 public otherBips = 2000; // 20%

    struct Round {
        uint256 roundId;
        uint256 poolId; // chosen by AVS when starting
        uint256 startTs;
        uint256 deadline;
        address leader;
        uint256 pot; // wei collected
        uint256 ticketCount;
        uint256 ticketPrice; // current ticket price for next purchase (wei)
        bool finalized;
    }

    mapping(uint256 => Round) public rounds;
    // Tracks whether a round's prize has been awarded to prevent double-award
    mapping(uint256 => bool) public roundAwarded;

    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);
    event AVSSet(address indexed avs);
    event ShareSplitterSet(address indexed splitter);
    event PrizeBoxSet(address indexed prizeBox);
    event RoundStarted(uint256 indexed roundId, uint256 indexed poolId, uint256 startTs, uint256 deadline, uint256 ticketPrice);
    event TicketBought(uint256 indexed roundId, address indexed buyer, uint256 amountPaid, uint256 newTicketPrice, uint256 deadline);
    event RoundFinalized(uint256 indexed roundId, address indexed winner, uint256 prizeBoxPortion, uint256 lpPortion, uint256 otherPortion);
    event FundsSplit(uint256 indexed roundId, uint256 prizeBoxAmount, uint256 lpAmount, uint256 otherAmount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Shaker: only owner");
        _;
    }

    modifier onlyAVS() {
        require(msg.sender == avs, "Shaker: only AVS");
        _;
    }

    modifier nonReentrant() {
        // simple reentrancy guard via tx-level mutex (lightweight)
        require(_locked == 1, "Shaker: reentrant");
        _locked = 2;
        _;
        _locked = 1;
    }

    uint256 private _locked = 1;

    constructor(address _shareSplitter, address _prizeBox, address _avs) {
        owner = msg.sender;
        shareSplitter = IShareSplitter(_shareSplitter);
        prizeBoxContract = IPrizeBox(_prizeBox);
        avs = _avs;
        emit OwnershipTransferred(address(0), owner);
        emit ShareSplitterSet(_shareSplitter);
        emit PrizeBoxSet(_prizeBox);
        emit AVSSet(_avs);
        nextRoundId = 1;
    }

    // Admin setters
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Shaker: zero owner");
        address old = owner;
        owner = newOwner;
        emit OwnershipTransferred(old, newOwner);
    }

    function setAVS(address _avs) external onlyOwner {
        avs = _avs;
        emit AVSSet(_avs);
    }

    function setShareSplitter(address _splitter) external onlyOwner {
        shareSplitter = IShareSplitter(_splitter);
        emit ShareSplitterSet(_splitter);
    }

    function setPrizeBox(address _prizeBox) external onlyOwner {
        prizeBoxContract = IPrizeBox(_prizeBox);
        emit PrizeBoxSet(_prizeBox);
    }

    function setTicketStartPrice(uint256 p) external onlyOwner {
        ticketStartPrice = p;
    }

    function setIncrementBips(uint256 bips) external onlyOwner {
        incrementBips = bips;
    }

    function setRoundDuration(uint256 secs) external onlyOwner {
        roundDuration = secs;
    }

    function setSplits(uint256 prizeBips, uint256 _lpBips, uint256 _otherBips) external onlyOwner {
        require(prizeBips + _lpBips + _otherBips == BIPS_DENOM, "Shaker: splits must sum 10000");
        prizeBoxesBips = prizeBips;
        lpBips = _lpBips;
        otherBips = _otherBips;
    }

    /// @notice AVS starts a round for a given poolId. AVS supplies the poolId to be shaking.
    function startRound(uint256 poolId) external onlyAVS returns (uint256) {
        uint256 rid = nextRoundId++;
        Round storage r = rounds[rid];
        r.roundId = rid;
        r.poolId = poolId;
        r.startTs = block.timestamp;
        r.deadline = block.timestamp + roundDuration;
        r.ticketPrice = ticketStartPrice;
        r.pot = 0;
        r.ticketCount = 0;
        r.leader = address(0);
        r.finalized = false;
        emit RoundStarted(rid, poolId, r.startTs, r.deadline, r.ticketPrice);
        return rid;
    }

    /// @notice Buy a ticket for an active round. Caller must send >= current ticket price. Overpayment is accepted but not refunded.
    function buyTicket(uint256 roundId) external payable nonReentrant {
        Round storage r = rounds[roundId];
        require(r.roundId == roundId, "Shaker: round not found");
        require(!r.finalized, "Shaker: round finalized");
        require(block.timestamp <= r.deadline, "Shaker: round expired");

        uint256 price = r.ticketPrice;
        require(msg.value >= price, "Shaker: insufficient payment");

        // Accept payment (overpayment kept)
        r.pot += msg.value;
        r.ticketCount += 1;

        // Update leader and restart timer
        r.leader = msg.sender;
        r.deadline = block.timestamp + roundDuration;

        // Increase ticket price by incrementBips (compounding)
        // newPrice = price * (10000 + incrementBips) / 10000
        uint256 newPrice = (price * (BIPS_DENOM + incrementBips)) / BIPS_DENOM;
        // Avoid zero-edge
        if (newPrice == 0) newPrice = 1;
        r.ticketPrice = newPrice;

        emit TicketBought(roundId, msg.sender, msg.value, newPrice, r.deadline);
    }

    /// @notice Finalize a round. AVS must call after deadline. AVS provides an array of boxIds to receive the prizeBox portion.
    /// @param roundId round to finalize
    /// @param boxIds list of boxIds that will receive portions of the prizeBox allocation (must be >0 if prizeBox portion >0)
    /// @param seed pseudo-random seed provided by AVS to distribute prizeBox amounts across boxIds
    function finalizeRound(uint256 roundId, uint256[] calldata boxIds, uint256 seed) external onlyAVS nonReentrant {
        Round storage r = rounds[roundId];
        require(r.roundId == roundId, "Shaker: round not found");
        require(!r.finalized, "Shaker: already finalized");
        require(block.timestamp > r.deadline, "Shaker: deadline not passed");

        r.finalized = true;
        address winner = r.leader;

        uint256 pot = r.pot;
        if (pot == 0) {
            emit RoundFinalized(roundId, winner, 0, 0, 0);
            return;
        }

        // Compute splits
        uint256 prizeBoxAmount = (pot * prizeBoxesBips) / BIPS_DENOM;
        uint256 lpAmount = (pot * lpBips) / BIPS_DENOM;
        uint256 otherAmount = pot - prizeBoxAmount - lpAmount; // remainder

        // Forward LP and other portions to ShareSplitter (if set)
        if (address(shareSplitter) != address(0) && lpAmount > 0) {
            // send lp amount tagged to poolId
            // using call to forward ETH
            (bool sentLp, ) = address(shareSplitter).call{value: lpAmount}(abi.encodeWithSelector(IShareSplitter.receiveSplit.selector, r.poolId));
            require(sentLp, "Shaker: LP split failed");
        } else {
            // if no splitter, keep funds in contract (could be claimed by admin later)
        }

        // otherAmount sent to ShareSplitter as well via receiveSplit (for simplicity)
        if (address(shareSplitter) != address(0) && otherAmount > 0) {
            (bool sentOther, ) = address(shareSplitter).call{value: otherAmount}(abi.encodeWithSelector(IShareSplitter.receiveSplit.selector, r.poolId));
            require(sentOther, "Shaker: other split failed");
        }

        // Distribute prizeBoxAmount among provided boxIds pseudo-randomly
        if (prizeBoxAmount > 0 && boxIds.length > 0 && address(prizeBoxContract) != address(0)) {
            uint256 remaining = prizeBoxAmount;
            uint256 n = boxIds.length;
            for (uint256 i = 0; i < n; i++) {
                // Last index gets remaining to avoid rounding dust
                uint256 share;
                if (i == n - 1) {
                    share = remaining;
                } else {
                    // pseudo-random fraction [0..remaining]
                    uint256 pseudo = uint256(keccak256(abi.encodePacked(seed, roundId, i, blockhash(block.number - 1))));
                    uint256 randBips = pseudo % BIPS_DENOM; // 0..9999
                    share = (prizeBoxAmount * randBips) / BIPS_DENOM;
                    if (share > remaining) share = remaining;
                }
                remaining -= share;
                if (share == 0) continue;
                // deposit to prizeBox via interface (payable)
                prizeBoxContract.depositToBox{value: share}(boxIds[i]);
            }
        } else if (prizeBoxAmount > 0) {
            // no boxes provided: keep funds in contract (or forward to splitter)
        }

        emit FundsSplit(roundId, prizeBoxAmount, lpAmount, otherAmount);
        emit RoundFinalized(roundId, winner, prizeBoxAmount, lpAmount, otherAmount);
    }

    /// @notice Award a specific prize box to the winner of a finalized round.
    /// @dev AVS calls this after finalizeRound to assign the box to the winner. Prevents double-award.
    function awardWinnerBox(uint256 roundId, uint256 boxId) external onlyAVS nonReentrant {
        Round storage r = rounds[roundId];
        require(r.roundId == roundId, "Shaker: round not found");
        require(r.finalized, "Shaker: round not finalized");
        require(!roundAwarded[roundId], "Shaker: already awarded");
        address winner = r.leader;
        require(winner != address(0), "Shaker: no winner");

        // Mark awarded before external call to avoid reentrancy issues
        roundAwarded[roundId] = true;

        // Call PrizeBox to transfer/assign box to winner
        prizeBoxContract.awardBoxTo(boxId, winner);

        emit RoundFinalized(roundId, winner, 0, 0, 0); // extra signal (optional)
    }

    // Allow contract to receive ETH (e.g., leftover or admin funds)
    receive() external payable {}
}