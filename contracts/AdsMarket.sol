pragma solidity ^0.8.0;

import "./Post.sol";
import "./Token.sol";

contract AdsMarket {
	Post postContract;
	Token tokenContract;
	uint256 ADVERTISING_COST_PER_DAY = 1; // in tokens
	uint256 nextPayout;

	constructor(Post _postContract, Token _tokenContract) {
		postContract = _postContract;
		tokenContract = _tokenContract;
		nextPayout = block.timestamp + 30 days; // set next payout to 1 month
	}

	modifier canPayout() {
		require(block.timestamp >= nextPayout, "next payout time has not been reached");
		nextPayout = block.timestamp + 30 days; // set next payout to 1 month
		_;
	}

	// returns id of ad post created
	function createAd(string memory caption, string memory ipfsCID, uint daysToAdvertise) public returns (uint) {
		uint tokensRequired = daysToAdvertise * ADVERTISING_COST_PER_DAY;
		require(tokensRequired >= tokenContract.balanceOf(msg.sender), "you have insufficient tokens to advertise for the specified amount of days");
		tokenContract.transferFrom(msg.sender, address(this), tokensRequired);

		uint endTime = block.timestamp + daysToAdvertise * 1 days;
		return postContract.createAd(caption, ipfsCID, endTime);
	}

	function payout() public canPayout {
		address[] memory payees;
		uint[] memory payoutPortion;
		uint totalPortions;
		(payees, payoutPortion, totalPortions) = postContract.getAdRevenueDistribution();
		postContract.resetMonthlyViewCounts();

		uint totalAdRevenue = tokenContract.balanceOf(address(this));

		for (uint i = 0; i < payees.length ; i++) {
			address payee = payees[i];
			tokenContract.transfer(payee, totalAdRevenue * payoutPortion[i] / totalPortions);
		}
	}
}