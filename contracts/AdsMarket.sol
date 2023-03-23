pragma solidity ^0.8.0;

import "./Post.sol";
import "./Token.sol";
import "./User.sol";
import "./AdsMarketStorage.sol";

contract AdsMarket {
	address owner;
	Post postContract;
	Token tokenContract;
	User userContract;
	AdsMarketStorage storageContract;
	uint256 ADVERTISING_COST_PER_DAY = 1000; // in tokens
	uint256 PAYOUT_EVERY = 30 days;
	uint256 DISTRIBUTE_PERCENTAGE = 90; // percentage of the total ad revenue generated to distribute back to creators

	constructor(Post _postContract, Token _tokenContract, User _userContract, AdsMarketStorage _storageContract) {
		owner = msg.sender;
		postContract = _postContract;
		tokenContract = _tokenContract;
		userContract = _userContract;
		storageContract = _storageContract;
	}

	modifier canPayout() {
		require(block.timestamp >= storageContract.getNextPayoutTime(), "next payout time has not been reached");
		storageContract.setNextPayoutTime(block.timestamp + PAYOUT_EVERY); // set next payout to 1 month later
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
		tokenContract.transferFrom(msg.sender, address(storageContract), tokensRequired);
		storageContract.addAdsRevenueThisMonth(tokensRequired);

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

		uint adsRevenue = storageContract.getAdsRevenueThisMonth();
		uint distributeAmt = adsRevenue * DISTRIBUTE_PERCENTAGE / 100;

		for (uint i = 0; i < payees.length ; i++) {
			address payee = payees[i];
			storageContract.addPayout(payee, distributeAmt * payoutPortion[i] / totalPortions);
		}

		uint commissionAmt = adsRevenue - distributeAmt;
		storageContract.addPayout(owner, commissionAmt);
		storageContract.resetAdsRevenueThisMonth();
	}

	function getPayoutBalance() public view returns (uint) {
		return storageContract.getPayout(msg.sender);
	}

	function withdraw(uint amt) public {
		address payee = msg.sender;
		require(storageContract.getPayout(payee) >= amt, "amt specified is more than your payout");
		storageContract.withdraw(payee, amt);
	}
}