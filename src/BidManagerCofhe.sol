 // SPDX-License-Identifier: UNLICENSED
 pragma solidity ^0.8.19;

 import "./AccessControl.sol";
 import "@fhenixprotocol/cofhe-contracts/contracts/FHE.sol";

 /// @title BidManagerCofhe
 /// @notice COFHE-enabled BidManager that stores sensitive numeric bid fields as encrypted ciphertext types (euint*).
 ///         Off-chain AVS processes (with cofhejs and the runtime/mocks) will be able to unseal/decrypt ciphertexts.
 contract BidManagerCofhe {
     // Legacy owner retained for compatibility; prefer role-based checks via AccessControl.
     address public owner;
     AccessControl public accessControl;
     bytes32 public constant ROLE_BID_MANAGER_ADMIN = keccak256("ROLE_BID_MANAGER_ADMIN");

     uint256 public constant MIN_BID_WEI = 0.01 ether;
     uint32 public constant MAX_RUSH = 1000;

     struct Bid {
         // encrypted sensitive fields
         eaddress bidderEnc;
         euint256 totalBidAmountEnc;
         euint256 maxSpendPerEpochEnc;
         euint256 minMintingRateEnc;
         euint32 rushFactorEnc;
         // non-sensitive metadata kept in plaintext
         uint64 createdEpoch;
         uint64 lastUpdatedEpoch;
     }

     mapping(address => Bid) private bids;
     mapping(uint256 => bool) public epochProcessed;
     mapping(address => bool) public settlementRole;

     event BidCreatedEncrypted(address indexed bidderPlain, bytes32 bidderEncHash);
     event BidUpdatedRushEncrypted(address indexed bidderPlain, bytes32 rushEncHash, uint64 effectiveEpoch);
     event EpochFinalized(uint256 indexed epoch, address indexed operator);
     event SettlementRoleUpdated(address indexed operator, bool enabled);

     modifier onlySettlement() {
         require(settlementRole[msg.sender], "Caller is not settlement role");
         _;
     }

     constructor(AccessControl _accessControl) {
         owner = msg.sender;
         accessControl = _accessControl;
     }

     function setSettlementRole(address operator, bool enabled) external {
         require(_isAdmin(msg.sender), "BidManagerCofhe: not admin");
         settlementRole[operator] = enabled;
         emit SettlementRoleUpdated(operator, enabled);
     }

     /// @notice Create a bid with ciphertext parameters. Plain ETH payment still required for on-chain value and guarantees.
     /// @dev Off-chain tooling should produce `inEuint256` / `inEuint32` values which are passed to the contract as calldata.
     ///      The contract converts them to `e*` types with FHE.asE* which implicitly verifies signatures when using a runtime.
     function createBid(
         inEuint256 calldata totalBidAmountIn,
         inEuint256 calldata maxSpendPerEpochIn,
         inEuint256 calldata minMintingRateIn,
         inEuint32 calldata rushFactorIn,
         inEaddress calldata bidderEncIn
     ) external payable {
         require(msg.value >= MIN_BID_WEI, "Bid below minimum");
         // enforce single bid per address (plain address key)
         require(bids[msg.sender].createdEpoch == 0, "Bid exists");

         // convert inputs to encrypted storage types (calls FHE.asE* under the hood)
         euint256 totalEnc = FHE.asEuint256(totalBidAmountIn);
         euint256 maxEnc = FHE.asEuint256(maxSpendPerEpochIn);
         euint256 minEnc = FHE.asEuint256(minMintingRateIn);
         euint32 rushEnc = FHE.asEuint32(rushFactorIn);
         eaddress bidderEnc = FHE.asEaddress(bidderEncIn);

         // store ciphertexts
         bids[msg.sender] = Bid({
             bidderEnc: bidderEnc,
             totalBidAmountEnc: totalEnc,
             maxSpendPerEpochEnc: maxEnc,
             minMintingRateEnc: minEnc,
             rushFactorEnc: rushEnc,
             createdEpoch: uint64(block.timestamp),
             lastUpdatedEpoch: uint64(block.timestamp)
         });

         // Allow this contract to operate on the ciphertexts (internal ops)
         // and optionally allow the caller (msg.sender) to read their own ciphertexts.
         FHE.allowThis(totalEnc);
         FHE.allowSender(totalEnc);

         // Emit event for off-chain operators to detect new encrypted bids; include a hash reference for indexers.
         emit BidCreatedEncrypted(msg.sender, keccak256(abi.encodePacked(totalEnc)));
     }

     /// @notice Returns encrypted fields for a bidder. Off-chain AVS will unseal/decrypt using cofhejs/mocks.
     function getBidEncrypted(address bidder) external view returns (
         eaddress bidderEnc,
         euint256 totalBidAmountEnc,
         euint256 maxSpendPerEpochEnc,
         euint256 minMintingRateEnc,
         euint32 rushFactorEnc,
         uint64 createdEpoch,
         uint64 lastUpdatedEpoch
     ) {
         Bid storage b = bids[bidder];
         return (
             b.bidderEnc,
             b.totalBidAmountEnc,
             b.maxSpendPerEpochEnc,
             b.minMintingRateEnc,
             b.rushFactorEnc,
             b.createdEpoch,
             b.lastUpdatedEpoch
         );
     }

     /// @notice Admin helper to grant off-chain AVS (or any account) permission to read a bidder's encrypted fields.
     ///         This uses FHE.allow which updates access control for ciphertexts so a runtime or coprocessor can decrypt for that account.
     function allowBidRead(address bidder, address avs, bool allow) external {
         require(_isAdmin(msg.sender), "BidManagerCofhe: not admin");
         Bid storage b = bids[bidder];
         require(b.createdEpoch != 0, "Unknown bid");

         if (allow) {
             FHE.allow(b.totalBidAmountEnc, avs);
             FHE.allow(b.maxSpendPerEpochEnc, avs);
             FHE.allow(b.minMintingRateEnc, avs);
             FHE.allow(b.rushFactorEnc, avs);
             FHE.allow(b.bidderEnc, avs);
         } else {
             // There is no revoke primitive in some runtimes; provide a simple pattern: allowTransient for one-time reads
             FHE.allowTransient(b.totalBidAmountEnc, avs);
             FHE.allowTransient(b.maxSpendPerEpochEnc, avs);
             FHE.allowTransient(b.minMintingRateEnc, avs);
             FHE.allowTransient(b.rushFactorEnc, avs);
             FHE.allowTransient(b.bidderEnc, avs);
         }
     }

     /// @notice Finalize an epoch by consuming plain amounts provided by settlement role.
     /// @dev For simplicity, consumption is performed in plaintext here. In a real migration you'd consume encrypted amounts
     ///      or submit encrypted consume proofs — that design is out of scope for this example.
     function finalizeEpochConsumeBids(
         uint256 epoch,
         address[] calldata biddersPlain,
         uint256[] calldata consumedAmountsPlain
     ) external onlySettlement {
         require(!epochProcessed[epoch], "Epoch already processed");
         require(biddersPlain.length == consumedAmountsPlain.length, "Mismatched arrays");

         // This example deducts from encrypted balances by publishing a subtraction task.
         // Real implementations would either accept an encrypted consume or rely on admin to reconcile off-chain + on-chain transfers.
         for (uint256 i = 0; i < biddersPlain.length; i++) {
             address bidderAddr = biddersPlain[i];
             uint256 consume = consumedAmountsPlain[i];
             // Emit an event that off-chain components can correlate and then update encrypted state via a dedicated function if needed.
             // For simplicity we do not mutate encrypted ciphertexts on-chain here.
             if (consume > 0) {
                 emit BidConsumedPlain(bidderAddr, consume);
             }
         }

         epochProcessed[epoch] = true;
         emit EpochFinalized(epoch, msg.sender);
     }

     // Auxiliary events and helpers
     event BidConsumedPlain(address indexed bidder, uint256 amount);
     function _isAdmin(address user) internal view returns (bool) {
         if (address(accessControl) != address(0)) {
             return accessControl.hasRole(ROLE_BID_MANAGER_ADMIN, user);
         }
         return user == owner;
     }
 }