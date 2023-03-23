pragma solidity ^0.8.0;

import {ContentModerationStorage as CMS} from "./ContentModerationStorage.sol";
import "./RNG.sol";
import "./Post.sol";
import "./User.sol";	
import "./Token.sol";

contract ContentModeration {
	CMS storageContract;
	RNG rngContract;
	Token tokenContract;
	Post postContract;
	User userContract;

	// fraction of how much to redistribute the rewards pool between approve and reject upon ending a dispute
	uint REDISTRIBUTE_REWARDS_FRACTION = 5;
	// minimum vote count to decide if a vote result can be used. a vote with a small vote count can have inaccurate results.
	uint MIN_VOTE_COUNT = 10;
	// amount that users have to lock to open a dispute. returned only if post was truly wrongly flagged.
	uint OPEN_DISPUTE_LOCKED_AMT = 1000; 
	// amount that users have to lock to vote. if voters of the majority votes will get rewarded.
	uint VOTE_LOCKED_AMT = 100;
	// minimum duration that a dispute must be open. this is to try to increase the number of votes to get more accurate results.
	uint MIN_DISPUTE_PERIOD = 1 days;

	constructor(CMS _storageContract, RNG _rngContract, Post _postContract, Token _tokenContract, User _userContract) {
		storageContract = _storageContract;
		rngContract = _rngContract;
		postContract = _postContract;
		tokenContract = _tokenContract;
		userContract = _userContract;
	}

	modifier validUser(address user) {
		require(userContract.validUser(user), "user does not exist");
		_;
	}

	modifier atVotingStage(CMS.VotingStage stage) {
		address voter = msg.sender;
		require(storageContract.getVotingStage(voter) == stage, "invalid voting stage");
		_;
	}

	// for creator whose posts has been flagged due to reportCount exceeding MAX_REPORT_COUNT,
	// the creator can open a dispute here. it requires the creartor to lock OPEN_DISPUTE_LOCKED_AMT amount of tokens to open a dispute.
	// the dispute can only be closed after the MIN_DISPUTE_PERIOD. this is to allow for more voters to vote on this dispute to get a more accurate result.
	// a disputer cannot have an open dispute and vote at the same time.
	function openDispute(uint postId, string memory reason) public atVotingStage(CMS.VotingStage.NOT_INVOLVED) {
		address creator = msg.sender;
		require(postContract.isCreatorOf(postId, creator), "only owner of this post can open a dispute");
		require(postContract.isFlagged(postId), "this post is not flagged, cant open dispute");
		require(!storageContract.isDisputed(postId), "there is already an ongoing dispute for this post");
		require(tokenContract.balanceOf(creator) >= OPEN_DISPUTE_LOCKED_AMT, "you do not have enough balance to open a dispute");

		// get locked tokens from disputer
		tokenContract.transferFrom(creator, address(tokenContract), OPEN_DISPUTE_LOCKED_AMT);

		uint endTime = block.timestamp + MIN_DISPUTE_PERIOD;
		storageContract.addDispute(creator, postId, reason, OPEN_DISPUTE_LOCKED_AMT, endTime);
	}

	// users can request for a random dispute to vote for . VOTE_LOCKED_AMT amount of tokens will be transferred from the voter to be locked in this dispute. 
	// a user can only vote for one dispute at any point of time.
	// this function returns a random disputeID to vote for.
	function allocateDispute() public validUser(msg.sender) atVotingStage(CMS.VotingStage.NOT_INVOLVED) returns (uint) {
		address voter = msg.sender;
		uint n = storageContract.getActiveDisputesCount();
		require(n > 0, "no active disputes to vote for now");
		// prevent disputers from voting on their own dispute
		require(storageContract.hasOpenDispute(voter), "you have an open dispute, therefore you cannot vote until your dispute is closed");
		require(tokenContract.balanceOf(voter) >= VOTE_LOCKED_AMT, "you do not have enough tokens to vote");

		// get locked tokens from voter
		tokenContract.transferFrom(voter, address(tokenContract), VOTE_LOCKED_AMT);
		// get random index from 0..n-1 to pick from the list of activeDisputes
		uint randIdx = rngContract.random() % n;
		// get dispute id that is randomly picked
		uint postId = storageContract.getActiveDisputeByIdx(randIdx);
		// add this voter to the dispute of post with id `postId`
		storageContract.addVoter(voter, postId);

		return postId;
	}	

	// the user can vote whether he approves or rejects the dispute.
	function vote(bool approve) public atVotingStage(CMS.VotingStage.HAVENT_VOTE) {
		address voter = msg.sender;
		uint postId = storageContract.getAllocatedDispute(voter);

		if (approve) {
			storageContract.approve(postId, voter);
		} else {
			storageContract.reject(postId, voter);
		}

		storageContract.addToVoterRewardPool(postId, VOTE_LOCKED_AMT);
	}	

	modifier canEndDispute(uint postId) {
		require(storageContract.isDisputed(postId), "dispute does not exist");
		require(storageContract.getEndTime(postId) <= block.timestamp, "the minimum endtime of the dispute has not been met");
		_;
	}

	// anyone can end the dispute, as long as it the endtime of the dispute has passed.
	function endDispute(uint postId) public canEndDispute(postId) {
		address creator = postContract.getCreator(postId);
		address[] memory approvers = storageContract.getApprovers(postId);
		uint numApprovers = approvers.length;
		address[] memory rejectors = storageContract.getRejectors(postId);
		uint numRejectors = rejectors.length;
		address[] memory haventVote = storageContract.getHaventVote(postId);
		uint numHaventVote = haventVote.length;
		uint numVoters = numApprovers + numRejectors;

		// refund those who havent vote
		for(uint i = 0; i < numHaventVote; i++) {
				tokenContract.transferTo(haventVote[i], VOTE_LOCKED_AMT);
		}
		
		// if we do not hit the minimum amount of voters, then we take it as the results of the dispute is not accurate, 
		// and therefore all parties are refunded their locked tokens. The dispute is deleted, but the post remains flagged.
		// the same applies for the case where the result is a tie.
		if (numVoters <= MIN_VOTE_COUNT || numApprovers == numRejectors) {
			tie(postId, creator);
		} else if (numApprovers > numRejectors) {
			approveWin(postId, creator);
		} else { // numRejectors > numApprovers
			rejectWin(postId);	
		}

		// --- clean up ---
		storageContract.removeDispute(postId);
	}

	function tie(uint postId, address creator) private {
		// tie/did not hit min vote count
		// return all parties their locked tokens
		address[] memory approvers = storageContract.getApprovers(postId);
		uint numApprovers = approvers.length;
		address[] memory rejectors = storageContract.getRejectors(postId);
		uint numRejectors = rejectors.length;

		for(uint i = 0; i < numApprovers; i++) {
			tokenContract.transferTo(approvers[i], VOTE_LOCKED_AMT);
		}
		for(uint i = 0; i < numRejectors; i++) {
			tokenContract.transferTo(rejectors[i], VOTE_LOCKED_AMT);
		}
		tokenContract.transferTo(creator, OPEN_DISPUTE_LOCKED_AMT);
	}

	function approveWin(uint postId, address creator) private {
		uint n =  storageContract.getActiveDisputesCount();
		uint voterRewardPool = storageContract.getVoterRewardPool(postId);
		uint approveRewardPool = storageContract.getApproveRewardPool();
		uint rejectRewardPool = storageContract.getRejectRewardPool();

			address[] memory approvers = storageContract.getApprovers(postId);
		uint numApprovers = approvers.length;
		
		// approve to unflag this post.
		// the total reward pool (dispute.voterRewardPool + 1/n of contract's rewardPoolForApprove) is distributed equally amongst the approvers, where n = no. of activeDisputes
		uint totalRewardPool = voterRewardPool + approveRewardPool / n;
		uint rewardPerVoter = totalRewardPool / numApprovers;
		approveRewardPool -= approveRewardPool / n;

		for(uint i = 0; i < numApprovers; i++) {
			tokenContract.transferTo(approvers[i], rewardPerVoter);
		}

		// return the creator his locked tokens & unflag his post
		tokenContract.transferTo(creator, OPEN_DISPUTE_LOCKED_AMT);
		postContract.resetFlagAndReportCount(postId);

		// redistribute rewards to the other pool, to deincentivze users from blindly repeatedly voting this option 
		(approveRewardPool, rejectRewardPool) = redistribute(approveRewardPool, rejectRewardPool, true);
		storageContract.setApproveRewardPool(approveRewardPool);
			storageContract.setRejectRewardPool(rejectRewardPool);
	}

	function rejectWin(uint postId) private {
		uint n =  storageContract.getActiveDisputesCount();
		uint voterRewardPool = storageContract.getVoterRewardPool(postId);
		uint approveRewardPool = storageContract.getApproveRewardPool();
		uint rejectRewardPool = storageContract.getRejectRewardPool();	

		address[] memory rejectors = storageContract.getRejectors(postId);
		uint numRejectors = rejectors.length;

		// reject to unflag this post.
		// 1. creator's locked tokens are not returned and are distrubuted between the two reward pools.
		// 2. the total reward pool (dispute.voterRewardPool + 1/n of contract's rewardPoolForReject) is distributed amongst the rejectors, where n = no. of activeDisputes
		uint totalRewardPool = voterRewardPool + rejectRewardPool / n;
		uint rewardPerVoter = totalRewardPool / numRejectors;
		rejectRewardPool -= rejectRewardPool / n;

		for(uint i = 0; i < numRejectors; i++) {
			tokenContract.transferTo(rejectors[i], rewardPerVoter);
		}

		// firstly, split the number of penalized tokens evenly between the two pools
		approveRewardPool += OPEN_DISPUTE_LOCKED_AMT / 2;
		rejectRewardPool += OPEN_DISPUTE_LOCKED_AMT / 2;
		// then, redistribute accordingly			
		(approveRewardPool, rejectRewardPool) = redistribute(approveRewardPool, rejectRewardPool, false);
		storageContract.setApproveRewardPool(approveRewardPool);
		storageContract.setRejectRewardPool(rejectRewardPool);	
	}

	function redistribute(uint approveRewardPool, uint rejectRewardPool, bool approveWon) private view returns (uint, uint) {
		if (approveWon) {
			// if approve won, transfer some rewards from approve pool to reject pool.
			// this will deincentivize voters from blindly always voting on approve
			uint redistributeAmt = approveRewardPool / REDISTRIBUTE_REWARDS_FRACTION;
			approveRewardPool -= redistributeAmt;
			rejectRewardPool += redistributeAmt;
		} else { // reject won
			// if reject won, transfer some rewards from reject pool to approve pool.
			// this will deincentivize voters from blindly always voting on reject.
			uint redistributeAmt = rejectRewardPool / REDISTRIBUTE_REWARDS_FRACTION;
			rejectRewardPool -= redistributeAmt;
			approveRewardPool += redistributeAmt;
		}
		return (approveRewardPool, rejectRewardPool);
	}

	// voters can double check which dispute id they are voting for 
	function getAllocatedDispute() public view validUser(msg.sender) returns (uint) {
		address voter = msg.sender;
		require(!storageContract.notInvolved(voter), "you do not have a dispute to vote on currently");
		return storageContract.getAllocatedDispute(voter);
	}	

	// for post contract to check the dispute that the `user` is voting for
	function isVotingFor(address voter, uint postId) public view validUser(voter) returns (bool) {
		require(!storageContract.notInvolved(voter), "you do not have a dispute to vote on currently");		
		return storageContract.getAllocatedDispute(voter) == postId;
	}	

	function getReason(uint postId) public view returns (string memory) {
		require(storageContract.isDisputed(postId), "this dispute does not exist");
		return storageContract.getReason(postId);
	}		
}