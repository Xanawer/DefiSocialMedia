pragma solidity ^0.8.0;

import "./RNG.sol";
import "./Post.sol";
import "./Token.sol";
import "./User.sol";

contract ContentModeration {
	struct Dispute {
		// dispute id
		uint id;
		// owner of this dispute (same as post's owner)
		address owner;
		// post id
		uint postId;
		// reason for dispute
		string reason;
		// locked tokens by creator to open this dispute
		uint lockedTokens;
		// minimum endtime of this dispute. dispute cannot be closed before `endtime`.
		uint endtime;
		// approve vote count
		address[] approvers;
		// reject vote count
		address[] rejectors;
		// voters who havent vote
		address[] haventVote;
		// total amount in voter reward pool;
		uint voterRewardPool;
	}

	// minimum vote count to decide if a vote result can be used. a vote with a small vote count can have inaccurate results.
	uint MIN_VOTE_COUNT = 10;
	// amount that users have to lock to open a dispute. returned only if post was truly wrongly flagged.
	uint OPEN_DISPUTE_LOCKED_AMT = 1000; 
	// amount that users have to lock to vote. if voters of the majority votes will get rewarded.
	uint VOTE_LOCKED_AMT = 100;
	// minimum duration that a dispute must be open. this is to try to increase the number of votes to get more accurate results.
	uint MIN_DISPUTE_PERIOD = 1 days;
	// the next dispute id to assign.
	uint nextDisputeId = 1;
	// list of dispute ids (currently active disputes)
	uint256[] activeDisputes;
	// map of id to dispute struct
	mapping(uint => Dispute) idToDispute;
	// map of user/voter to their current dispute's id. if value is 0, then it means that the user is not voting for any dispute.
	mapping(address => uint) voterToDisputeId;
	// map of user to the count of currently active disputes opened by the user
	mapping(address => uint[]) usersToActiveDisputes;
	RNG rngContract;
	Post postContract;
	Token tokenContract;
	User userContract;
	// the reward pool of this contract comes from the locked tokens of disputes that were rejected
	uint rewardPoolForApprove = 0;
	uint rewardPoolForReject = 0;
	// fraction of how much to redistribute the rewards pool between approve and reject upon ending a dispute
	uint REDISTRIBUTE_REWARDS_FRACTION = 5;

	constructor(RNG _rngContract, Post _postContract, Token _tokenContract, User _userContract) {
		rngContract = _rngContract;
		postContract = _postContract;
		tokenContract = _tokenContract;
		userContract = _userContract;
	}

	modifier userExists(address user) {
		require(userContract.exists(user), "user does not exist");
		_;
	}

	// for creator whose posts has been flagged due to reportCount exceeding MAX_REPORT_COUNT,
	// the creator can open a dispute here. it requires the creartor to lock OPEN_DISPUTE_LOCKED_AMT amount of tokens to open a dispute.
	// the dispute can only be closed after the MIN_DISPUTE_PERIOD. this is to allow for more voters to vote on this dispute to get a more accurate result.
	// a disputer cannot have an open dispute and vote at the same time.
	function openDispute(uint postId, string memory reason) public {
		require(postContract.getOwner(postId) == msg.sender, "only owner of this post can open a dispute");
		require(postContract.getFlaggedStatus(postId), "this post is not flagged, cant open dispute");
		require(tokenContract.balanceOf(msg.sender) >= OPEN_DISPUTE_LOCKED_AMT, "you do not have enough balance to open a dispute");
		uint[] storage disputes = usersToActiveDisputes[msg.sender];
		for (uint i = 0; i < disputes.length; i++) {
			uint disputeId = disputes[i];
			require(idToDispute[disputeId].postId != postId, "there is already an ongoing dispute for this post");
		}

		// get locked tokens from disputer
		tokenContract.transferFrom(msg.sender, address(this), OPEN_DISPUTE_LOCKED_AMT);

		Dispute storage dispute = idToDispute[nextDisputeId];
		dispute.id = nextDisputeId;
		dispute.postId = postId;
		dispute.owner = msg.sender;
		dispute.reason = reason;
		dispute.lockedTokens = OPEN_DISPUTE_LOCKED_AMT;
		dispute.endtime = block.timestamp + MIN_DISPUTE_PERIOD;

		// add to list of activeDisputes
		activeDisputes.push(dispute.id);
		// update nextDisputeId
		nextDisputeId++;
		// update the active disptue counts of this user
		usersToActiveDisputes[msg.sender].push(dispute.id);
	}

	// users can request for a random dispute to vote for . VOTE_LOCKED_AMT amount of tokens will be transferred from the voter to be locked in this dispute. 
	// a user can only vote for one dispute at any point of time.
	// this function returns a random disputeID to vote for.
	function getNewRandomDispute() public userExists(msg.sender) returns (uint) {
		uint n = activeDisputes.length;
		// prevent disputers from voting on their own dispute
		require(usersToActiveDisputes[msg.sender].length == 0, "you have an open dispute, therefore you cannot vote until your dispute is closed");

		require(voterToDisputeId[msg.sender] == 0, "you have already voted for a dispute. you can only vote for one dispute at a time");
		require(n > 0, "no active disputes to vote for now");
		require(tokenContract.balanceOf(msg.sender) >= VOTE_LOCKED_AMT, "you do not have enough tokens to vote");

		// get locked tokens from voter
		tokenContract.transferFrom(msg.sender, address(this), VOTE_LOCKED_AMT);
		// get random index from 0..n-1 to pick from the list of activeDisputes
		uint randIdx = rngContract.random() % n;
		// get dispute id that is randomly picked
		uint disputeId = activeDisputes[randIdx];
		// keep track of which dispute id this voter is voting for
		voterToDisputeId[msg.sender] = disputeId;
		// add voter to list of voters who havent vote
		idToDispute[disputeId].haventVote.push(msg.sender);
		return disputeId;
	}

	// voters can double check which dispute id they are voting for 
	function getCurrentDisputeId() public view userExists(msg.sender) returns (uint) {
		require(voterToDisputeId[msg.sender] > 0, "you do not have a dispute to vote on currently");
		return voterToDisputeId[msg.sender];
	}

	// for post contract to check the dispute that the `user` is voting for
	function getCurrentDisputeIdOfUser(address user) public view returns (uint) {
		require(msg.sender == address(postContract), "only post contract can call getCurrentDisputeIdOfUser");
		require(voterToDisputeId[user] > 0, "the user does not have a dispute to vote on currently");
		return voterToDisputeId[user];
	}

	function getPostId(uint disputeId) public view returns (uint) {
		Dispute storage dispute = idToDispute[disputeId];
		require(dispute.id == disputeId, "this dispute does not exist");
		return dispute.postId;
	}

	function getReason(uint disputeId) public view returns (string memory) {
		Dispute storage dispute = idToDispute[disputeId];
		require(dispute.id == disputeId, "this dispute does not exist");
		return dispute.reason;
	}

	// the user can cast a vote on the dispute specified by `disputeId`.
	// the user can vote whether he approves or rejects the dispute.
	function vote(uint disputeId, bool approve) public {
		address voter = msg.sender;
		require(voterToDisputeId[voter] == disputeId, "you cannot vote for this dispute");
		
		Dispute storage dispute = idToDispute[disputeId];
		bool found = false;
		// remove from haventVote list
		for (uint i = 0; i < dispute.haventVote.length; i++) {
			if (dispute.haventVote[i] == voter) {
				found = true;
				dispute.haventVote[i] = dispute.haventVote[dispute.haventVote.length - 1];
				dispute.haventVote.pop();
				break;
			}
		}
		// if we cannot find the voter in the haventvote list, it means that the voter has already voted.
		require(found, "you have already voted");

		if (approve) {
			dispute.approvers.push(voter);
		} else {
			dispute.rejectors.push(voter);
		}

		// update voter reward pool for this dispute
		dispute.voterRewardPool += VOTE_LOCKED_AMT;
	}

	// anyone can end the dispute, as long as it the endtime of the dispute has passed.
	function endDispute(uint disputeId) public {
		Dispute storage dispute = idToDispute[disputeId];
		require(dispute.id == disputeId, "dispute does not exist"); // if dispute does not exist, dispute.id will be 0 (default value of non-existent key mapping)
		require(dispute.endtime <= block.timestamp, "the minimum endtime of the dispute has not been met");
		
		// if we do not hit the minimum amount of voters, then we take it as the results of the dispute is not accurate, 
		// and therefore all parties are refunded their locked tokens. The dispute is deleted, but the post remains flagged.
		// the same applies for the case where the result is a tie.
		uint numApprovers = dispute.approvers.length;
		uint numRejectors =  dispute.rejectors.length;
		uint numVoters = numApprovers + numRejectors;
		uint n = activeDisputes.length;

		if (numVoters <= MIN_VOTE_COUNT || numApprovers == numRejectors) {
			// tie/did not hit min vote count
			// return all parties their locked tokens
			for(uint i = 0; i < numApprovers; i++) {
				address voter = dispute.approvers[i];
				tokenContract.transfer(voter, VOTE_LOCKED_AMT);
				delete voterToDisputeId[voter];
			}
			for(uint i = 0; i < numRejectors; i++) {
				address voter = dispute.rejectors[i];
				tokenContract.transfer(voter, VOTE_LOCKED_AMT);
				delete voterToDisputeId[voter];
			}
			for(uint i = 0; i < dispute.haventVote.length; i++) {
				address voter = dispute.haventVote[i];
				tokenContract.transfer(voter, VOTE_LOCKED_AMT);
				delete voterToDisputeId[voter];
			}
			tokenContract.transfer(dispute.owner, OPEN_DISPUTE_LOCKED_AMT);
		} else if (numApprovers > numRejectors) {
			// approve to unflag this post.
			// 1. creator gets back his locked tokens. post gets unflagged.
			// 2. the total reward pool (dispute.voterRewardPool + 1/n of contract's rewardPoolForApprove) is distributed amongst the approvers
			// n = no. of activeDisputes
			uint totalRewardPool = dispute.voterRewardPool + rewardPoolForApprove / n;
			uint rewardPerVoter = totalRewardPool / numApprovers;
			rewardPoolForApprove -= rewardPoolForApprove / n;
			// distribute the rewards to the approvers
			for(uint i = 0; i < numApprovers; i++) {
				address voter = dispute.approvers[i];
				tokenContract.transfer(voter, rewardPerVoter);
				delete voterToDisputeId[voter];
			}
			// reset voter's dispute mapping
			for(uint i = 0; i < numRejectors; i++) {
				address voter = dispute.rejectors[i];
				delete voterToDisputeId[voter];
			}
			// return the locked tokens to those who havent vote
			for(uint i = 0; i < dispute.haventVote.length; i++) {
				address voter = dispute.haventVote[i];
				tokenContract.transfer(voter, VOTE_LOCKED_AMT);
				delete voterToDisputeId[voter];
			}
			// return the creator his locked tokens & unflag his post
			tokenContract.transfer(dispute.owner, OPEN_DISPUTE_LOCKED_AMT);
			postContract.resetFlagAndReportCount(dispute.postId);

			// redistribute rewards to the other pool, to deincentivze users from blindly repeatedly voting this option
			uint redistributeAmt = rewardPoolForApprove / REDISTRIBUTE_REWARDS_FRACTION;
			rewardPoolForApprove -= redistributeAmt;
			rewardPoolForReject += redistributeAmt;
		} else { // numRejectors > numApprovers
			// reject to unflag this post.
			// 1. creator's locked tokens are not returned and are distrubuted between the two reward pools.
			// 2. the total reward pool (dispute.voterRewardPool + 1/n of contract's rewardPoolForReject) is distributed amongst the rejectors
			// n = no. of activeDisputes
			uint totalRewardPool = dispute.voterRewardPool + rewardPoolForReject / n;
			uint rewardPerVoter = totalRewardPool / numRejectors;
			rewardPoolForReject -= rewardPoolForReject / n;

			// transfer more rewards to the approve's reward pool, to deincentivze users from blindly repeatedly voting this option
			rewardPoolForReject += dispute.lockedTokens / REDISTRIBUTE_REWARDS_FRACTION;
			rewardPoolForApprove += dispute.lockedTokens * (1 - 1 / REDISTRIBUTE_REWARDS_FRACTION);
			// reset voter's dispute mapping
			for(uint i = 0; i < numApprovers; i++) {
				address voter = dispute.approvers[i];
				delete voterToDisputeId[voter];
			}
			// distribute the rewards to the rejectors
			for(uint i = 0; i < numRejectors; i++) {
				address voter = dispute.rejectors[i];
				tokenContract.transfer(voter, rewardPerVoter);
				delete voterToDisputeId[voter];
			}
			// return the locked tokens to those who havent vote
			for(uint i = 0; i < dispute.haventVote.length; i++) {
				address voter = dispute.haventVote[i];
				tokenContract.transfer(voter, VOTE_LOCKED_AMT);
				delete voterToDisputeId[voter];
			}
		}

		// --- clean up ---
		// remove the dispute id from the list of user's active disputes
		uint[] storage userDisputes = usersToActiveDisputes[dispute.owner];
		for (uint i = 0; i < userDisputes.length; i++) {
			if (userDisputes[i] == disputeId) {
				userDisputes[i] = userDisputes[userDisputes.length - 1];
				userDisputes.pop();
				break;
			}
		}
		// remove the dispute id from the list of overall active disptues
		for (uint i = 0; i < activeDisputes.length; i++) {
			if (activeDisputes[i] == disputeId) {
				activeDisputes[i] = activeDisputes[activeDisputes.length - 1];
				activeDisputes.pop();
				break;
			}
		}
		// delete the dispute struct
		delete idToDispute[disputeId];
	}
}