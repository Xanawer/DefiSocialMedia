pragma solidity ^0.8.0;

import "./Authorizable.sol";

contract FeedStorage is Authorizable {
	// stores all posts (only storing the ids) to generate the feed for users
	// latest posts are always at the end of the array
	uint256[] globalFeed;
	// keep track of scroll states. 
	// scroll states tell us which post of the globalFeed did the user last scrolled until
	// this allow us to return the next N posts from the last-scrolled-until post
	mapping(address => uint256) scrollStates;	

	function init(address feedAddr) public ownerOnly {
		authorizeContract(feedAddr);
	}

	function addToFeed(uint postId) external isAuthorized {
		globalFeed.push(postId);
	}

	function getPostIdByIdx(uint idx) external view isAuthorized returns (uint) {
		return globalFeed[idx];
	}	

	function getGlobalFeedSize() external view isAuthorized returns (uint) {
		return globalFeed.length;
	}

	function getScrollState(address user) external view isAuthorized returns (uint) {
		return scrollStates[user];
	}

	function setScrollState(address user, uint idx) external isAuthorized {
		scrollStates[user] = idx;
	}
}