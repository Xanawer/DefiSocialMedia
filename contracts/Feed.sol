pragma solidity ^0.8.0;

import "./Post.sol";

contract Feed {
	Post postContract;

	// stores all posts (only storing the ids) to generate the feed for users
	// latest posts are always at the end of the array
	uint256[] globalFeed;
	// keep track of scroll states. 
	// scroll states tell us which post of the globalFeed did the user last scrolled until
	// this allow us to return the next N posts from the last-scrolled-until post
	mapping(address => uint256) scrollStates;
	uint256 POSTS_PER_SCROLL = 10;
	// the index at which to inject an advertisement on each scroll
	uint256 INSERT_AD_AT_IDX = POSTS_PER_SCROLL / 2;

	constructor(Post _postContract) {
		postContract = _postContract;
	}

	modifier postContractOnly() {
		require(msg.sender == address(postContract), "post contract only");
		_;
	}

	// adds this post to the global feed
	function addToFeed(uint256 postId) public postContractOnly {
		globalFeed.push(postId);
	}

	// initializes the start of a scroll.
	// this returns the latest N posts, where N=POSTS_PER_SCROLL specified at the start of this contract
	function startScroll() public returns (Post.PostData[] memory) {
		// start idx = last element of array (where the lastest post is at)
		return scrollPosts(globalFeed.length - 1);
	}

	// continues the scroll.
	// this returns the next N posts, starting from where the user last left off, as captured by the `scrollStates` mapping
	function continueScroll() public returns (Post.PostData[] memory) {
		// start idx = the latest post which the user has not seen according to `scrollStates`
		return scrollPosts(scrollStates[msg.sender]);
	}

	// return the next 10 (non-deleted && non-flagged) posts starting from startIdx.
	// note that we count from the end of array to start of array, as the latest posts are the end of the array.
	function scrollPosts(uint startIdx) private returns (Post.PostData[] memory) {
		require(startIdx >= 0 && globalFeed.length > 0 , "no more posts to scroll");

		uint numPosts = 0;
		uint idx = startIdx;
		Post.PostData[] memory posts = new Post.PostData[](POSTS_PER_SCROLL);
		// add up to `POSTS_PER_SCROLL` posts to result, or until there is no more posts from global feed to return (i.e idx < 0)
		while (numPosts < POSTS_PER_SCROLL && idx >= 0) {
			// ADVERTISMENT INJECTION
			if (numPosts == INSERT_AD_AT_IDX) {
				bool found;
				Post.Ad memory ad;
				(ad, found) = postContract.getAd();
				if (found) {
					posts[numPosts] = ad.postData;
					numPosts++;
					continue;
				}
				// if we cannot find an ad.. continue adding more posts from global feed
			}

			uint postId = globalFeed[idx];
			if (postContract.notDeletedOrFlagged(postId) && postContract.canViewCreatorPosts(postContract.getOwner(postId), msg.sender)) {
				posts[numPosts] = postContract.getPost(postId);
				numPosts++;
			} 
			idx--;
		}

		// for next scroll, we start searching from this index
		scrollStates[msg.sender] = idx; 

		return posts;
	}
}