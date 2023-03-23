pragma solidity ^0.8.0;

import "./Post.sol";
import "./Token.sol";
import "./User.sol";

contract AdsMarket {
	address owner;
	Post postContract;
	Token tokenContract;
	User userContract;
	uint256 ADVERTISING_COST_PER_DAY = 1000; // in tokens
	uint256 nextPayout; // time of next payout
	uint256 DISTRIBUTE_PERCENTAGE = 90; // percentage of the total ad revenue generated to distribute back to creators
	uint adsRevenue;

	constructor(Post _postContract, Token _tokenContract, User _userContract) {
		owner = msg.sender;
		postContract = _postContract;
		tokenContract = _tokenContract;
		userContract = _userContract;
		nextPayout = block.timestamp + 30 days; // set next payout to 1 month
	}

	modifier canPayout() {
		require(block.timestamp >= nextPayout, "next payout time has not been reached");
		nextPayout = block.timestamp + 30 days; // set next payout to 1 month later
		_;
	}

	modifier validUser(address user) {
		require(userContract.validUser(user), "user does not exist");
		_;
	}
	
	// creates an ad with the specified arguments. this function assumes the user has approved the `tokensRequired` amount of tokens to transfer to this contract.
	// returns id of ad post created.
	function createAd(string memory caption, string memory ipfsCID, uint daysToAdvertise) public validUser(msg.sender) returns (uint) {
		uint tokensRequired = daysToAdvertise * ADVERTISING_COST_PER_DAY;
		require(tokensRequired >= tokenContract.balanceOf(msg.sender), "you have insufficient tokens to advertise for the specified amount of days");
		tokenContract.transferFrom(msg.sender, address(tokenContract), tokensRequired);
		adsRevenue += tokensRequired;

		uint endTime = block.timestamp + daysToAdvertise * 1 days;
		return postContract.createAd(msg.sender, caption, ipfsCID, endTime);
	}

	// triggers the payout mechanism of ad revenue. This can only be triggered once every month (enforced by canPayout).
	// totalAdRevenue = balance of this contract.
	// we distribute 90% of the ad revenue back to the creators, and the other 10% is sent to the contract owner.
	// the distribution of the ad revenue is porportional to the amount of views creators accumlated for the current monthly period.
	function payout() public canPayout {
		address[] memory payees;
		uint[] memory payoutPortion;
		uint totalPortions;
		(payees, payoutPortion, totalPortions) = postContract.getAdRevenueDistribution();
		postContract.resetMonthlyViewCounts();

		uint distributeAmt = adsRevenue * DISTRIBUTE_PERCENTAGE / 100;
		adsRevenue -= distributeAmt;

		for (uint i = 0; i < payees.length ; i++) {
			address payee = payees[i];
			tokenContract.transferTo(payee, distributeAmt * payoutPortion[i] / totalPortions);
		}

		uint commissionAmt = adsRevenue;
		adsRevenue = 0;
		tokenContract.transferTo(owner, commissionAmt);
	}
}