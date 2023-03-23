pragma solidity ^0.8.0;

import './Token.sol';
import "./Authorizable.sol";

contract ContentModerationStorage is Authorizable {
	struct Dispute {
		// owner of this dispute (same as post's owner)
		address owner;
		// post id (unique identifier of disputes, since a post can only have at most 1 dispute)
		uint postId;
		// reason for dispute
		string reason;
		// locked tokens by creator to open this dispute
		uint lockedTokens;
		// minimum endtime of this dispute. dispute cannot be closed before `endtime`.
		uint endTime;
		// approve vote count
		address[] approvers;
		// reject vote count
		address[] rejectors;
		// voters who havent vote
		address[] haventVote;
		// total amount in voter reward pool;
		uint voterRewardPool;
		// index of this dispute in the activeDisputes array
		uint activeDisputesIdx;
		// whether this dispute is active
		bool active;
	}

	// not involved: no dispute allocated to this voter to vote for
	// havent_vote: has a dispute allocated to this voter, but havent vote for it
	// voted: voted for the allocated dispute
	enum VotingStage {NOT_INVOLVED, HAVENT_VOTE, VOTED}

	struct VoterData {
		uint postId;
		VotingStage stage;
		// index of this voter in the haventVote array in Dispute
		uint haventVoteIdx;
	}

	struct DisputerData {
		mapping(uint => bool) postHasDispute;
		uint activeDisputeCount;
	}

	Token tokenContract;
	// list of post ids that have active disputes (currently active disputes)
	uint256[] activeDisputes;
	// map of post id to dispute struct
	mapping(uint => Dispute) disputes;
	mapping(address => VoterData) voters;
	mapping(address => DisputerData) disputers;
	// the reward pool of this contract comes from the locked tokens of disputes that were rejected
	uint approveRewardPool = 0;
	uint rejectRewardPool = 0;	
	// balance of unlocked tokens that users can withdraw
	mapping(address => uint) unlockedBalance;

	constructor(Token _tokenContract) {
		tokenContract = _tokenContract;
	}

	function init(address cmLogic) public ownerOnly {
		authorizeContract(cmLogic);
	}

	// === CORE LOGIC ===
	function addDispute(address creator, uint postId, string memory reason, uint lockedTokens, uint endTime) external isAuthorized {
		Dispute storage dispute = disputes[postId];
		dispute.postId = postId;
		dispute.owner = creator;
		dispute.reason = reason;
		dispute.lockedTokens = lockedTokens;
		dispute.endTime = endTime;
		dispute.voterRewardPool = 0;
		dispute.active = true;
		dispute.activeDisputesIdx = activeDisputes.length;
		// reset arrays 
		delete dispute.approvers;
		delete dispute.rejectors;
		delete dispute.haventVote;

		activeDisputes.push(postId);

		DisputerData storage disputerData = disputers[creator];
		disputerData.postHasDispute[postId] = true;
		disputerData.activeDisputeCount++;
	}

	function addVoter(address voter, uint postId) external isAuthorized {
		VoterData storage voterData = voters[voter];
		Dispute storage dispute = disputes[postId];

		voterData.postId = postId;
		voterData.stage = VotingStage.HAVENT_VOTE;
		voterData.haventVoteIdx = dispute.haventVote.length;

		dispute.haventVote.push(voter);
	}
	
	function removeFromHaventVote(uint postId, address voter) private isAuthorized {
		address[] storage haventVote = disputes[postId].haventVote;
		uint idx = voters[voter].haventVoteIdx;

		// remove from havent vote array
		address lastVoter = haventVote[haventVote.length - 1];
		haventVote[idx] = lastVoter;
		haventVote.pop();
		voters[lastVoter].haventVoteIdx = idx;
	}

	function approve(uint postId, address voter) external isAuthorized {
		removeFromHaventVote(postId, voter);

		Dispute storage dispute = disputes[postId];
		dispute.approvers.push(voter);

		voters[voter].stage = VotingStage.VOTED;
	}

	function reject(uint postId, address voter) external isAuthorized {
		removeFromHaventVote(postId, voter);

		Dispute storage dispute = disputes[postId];
		dispute.rejectors.push(voter);

		voters[voter].stage = VotingStage.VOTED;
	}

	function addToVoterRewardPool(uint postId, uint amt) external isAuthorized {
		disputes[postId].voterRewardPool += amt;
	}

	function removeDispute(uint postId) external isAuthorized {
		// remove from global active disputes array
		removeFromActiveDisputesArr(postId);
		// reset disputer
		disputerDone(postId);
		// reset voter
		Dispute storage dispute = disputes[postId];
		resetVoters(dispute.approvers);
		resetVoters(dispute.rejectors);
		resetVoters(dispute.haventVote);
		// delete dispute
		delete disputes[postId];
	}

	function removeFromActiveDisputesArr(uint postId) private isAuthorized {
		uint idx = disputes[postId].activeDisputesIdx;
		uint lastDispute = activeDisputes[activeDisputes.length - 1];
		activeDisputes[idx] = lastDispute;
		activeDisputes.pop();
		disputes[lastDispute].activeDisputesIdx = idx;
	}

	function resetVoters(address[] memory votersArr) private isAuthorized {
		for (uint i = 0; i < votersArr.length; i++) {
			delete voters[votersArr[i]];
		}
	}

	function disputerDone(uint postId) private isAuthorized {
		address creator = disputes[postId].owner;
		disputers[creator].postHasDispute[postId] = false;
		disputers[creator].activeDisputeCount--;
	}	

	function getBalance(address user) external view isAuthorized returns (uint) {
		return unlockedBalance[user];
	}

	function addBalance(address user, uint amt) external isAuthorized {
		unlockedBalance[user] += amt;
	}

	function batchAddBalance(address[] memory users, uint amt) external isAuthorized {
		for (uint i = 0; i < users.length; i++) {
			address user = users[i];
			unlockedBalance[user] += amt;
		}
	}	

	function withdraw(address user, uint amt) external isAuthorized {
		unlockedBalance[user] -= amt;
		tokenContract.transfer(user, amt);
	}

	// === GETTERS AND SETTERS === 
	function getVotingStage(address voter) external view isAuthorized returns (VotingStage) {
		return voters[voter].stage;
	}

	function notInvolved(address voter) external view isAuthorized returns (bool) {
		return voters[voter].stage == VotingStage.NOT_INVOLVED;
	}

	function isDisputed(uint postId) external view isAuthorized returns (bool) {
		return disputes[postId].active;
	}

	function getEndTime(uint postId) external view isAuthorized returns (uint) {
		return disputes[postId].endTime;
	}
	function getApprovers(uint postId) external view isAuthorized returns(address[] memory) {
		return disputes[postId].approvers;
	}

	function getRejectors(uint postId) external view isAuthorized returns(address[] memory) {
		return disputes[postId].rejectors;
	}

	function getHaventVote(uint postId) external view isAuthorized returns(address[] memory) {
		return disputes[postId].haventVote;
	}	

	function getActiveDisputesCount() external view isAuthorized returns(uint) {
		return activeDisputes.length;
	}

	function getApproveRewardPool() external view isAuthorized returns(uint) {
		return approveRewardPool;
	}

	function getRejectRewardPool() external view isAuthorized returns(uint) {
		return rejectRewardPool;
	}

	function getVoterRewardPool(uint postId) external view isAuthorized returns(uint) {
		return disputes[postId].voterRewardPool;
	}

	function setApproveRewardPool(uint amt) external isAuthorized {
		approveRewardPool = amt;
	}

	function setRejectRewardPool(uint amt) external isAuthorized {
		rejectRewardPool = amt;
	}

	function hasOpenDispute(address creator) external view isAuthorized returns (bool) {
		return disputers[creator].activeDisputeCount > 0;
	}

	function getAllocatedDispute(address voter) external view isAuthorized returns (uint) {
		return voters[voter].postId;
	}

	function getActiveDisputeByIdx(uint idx) external view isAuthorized returns (uint) {
		return activeDisputes[idx];
	}	

	function getReason(uint postId) external view isAuthorized returns (string memory) {
		return disputes[postId].reason;
	}	
}