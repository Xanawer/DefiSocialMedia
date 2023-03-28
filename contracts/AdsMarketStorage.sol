pragma solidity ^0.8.0;

import "./Authorizable.sol";
import "./Token.sol";

contract AdsMarketStorage is Authorizable {
	Token tokenContract;

	uint256 nextPayoutTime; // time of next payout
	uint adsRevenueThisMonth;
	mapping(address => uint) payouts;

	// === EVENTS ===
	event Withdraw(address withdrawer,uint amount);

	constructor(Token _tokenContract) {
		tokenContract = _tokenContract;		
	}

	function init(address adsMarket) public ownerOnly {
		authorizeContract(adsMarket);
	}

	function setNextPayoutTime(uint _nextPayoutTime) external isAuthorized {
		nextPayoutTime = _nextPayoutTime;
	}

	function getNextPayoutTime() external view isAuthorized returns (uint) {
		return nextPayoutTime;
	}

	function getAdsRevenueThisMonth() external view isAuthorized returns (uint) {
		return adsRevenueThisMonth;
	}

	function addAdsRevenueThisMonth(uint amt) external isAuthorized {
		adsRevenueThisMonth += amt;
	}	

	function resetAdsRevenueThisMonth() external isAuthorized {
		adsRevenueThisMonth = 0;
	}		

	function addPayout(address payee, uint amt) external isAuthorized {
		payouts[payee] += amt;
	}

	function getPayout(address payee) external view isAuthorized returns (uint)  {
		return payouts[payee];
	}

	function withdraw(address payee, uint amt) external isAuthorized {
		payouts[payee] -= amt;
		tokenContract.transfer(payee, amt);
		emit Withdraw(payee, amt);
	}
}