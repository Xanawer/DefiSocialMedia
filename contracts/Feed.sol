pragma solidity ^0.8.0;

import "./Post.sol";
import "./PostStorage.sol";
import "./FeedStorage.sol";

contract Feed {
	Post postContract;
	FeedStorage storageContract;
	PostStorage postStorageContract;
	uint256 POSTS_PER_SCROLL = 10;
	// the index at which to inject an advertisement on each scroll
	uint256 INSERT_AD_AT_IDX = POSTS_PER_SCROLL / 2;

	constructor(Post _postContract, PostStorage _postStorageContract, FeedStorage _storageContract) {
		postStorageContract = _postStorageContract;
		storageContract = _storageContract;
		postContract = _postContract;
	}

	modifier postContractOnly() {
		require(msg.sender == address(postContract), "post contract only");
		_;
	}

	// adds this post to the global feed
	function addToFeed(uint256 postId) public postContractOnly {
		storageContract.addToFeed(postId);
	}

	// initializes the start of a scroll.
	// this returns the latest N posts, where N=POSTS_PER_SCROLL specified at the start of this contract
	function startScroll() public returns (PostStorage.Post[] memory) {
		// start idx = last element of array (where the lastest post is at)
		return scrollPosts(storageContract.getGlobalFeedSize() - 1);
	}

	// continues the scroll.
	// this returns the next N posts, starting from where the user last left off, as captured by the `scrollStates` mapping
	function continueScroll() public returns (PostStorage.Post[] memory) {
		// start idx = the latest post which the user has not seen according to `scrollStates`
		return scrollPosts(storageContract.getScrollState(msg.sender));
	}

	// return the next 10 (non-deleted && non-flagged) posts starting from startIdx.
	// note that we count from the end of array to start of array, as the latest posts are the end of the array.
	function scrollPosts(uint startIdx) private returns (PostStorage.Post[] memory) {
		require(startIdx >= 0, "no more posts to scroll");
		address viewer = msg.sender;
		uint numPosts = 0;
		uint idx = startIdx;
		PostStorage.Post[] memory posts = new PostStorage.Post[](POSTS_PER_SCROLL);
		// add up to `POSTS_PER_SCROLL` posts to result, or until there is no more posts from global feed to return (i.e idx < 0)
		while (numPosts < POSTS_PER_SCROLL && idx >= 0) {
			// ADVERTISMENT INJECTION
			if (numPosts == INSERT_AD_AT_IDX) {
				bool found;
				PostStorage.Post memory adPost;
				(adPost, found) = postContract.getAdPost();
				if (found) {
					posts[numPosts] = adPost;
					numPosts++;
					continue;
				}
				// if we cannot find an ad.. continue adding more posts from global feed
			}

			uint postId = storageContract.getPostIdByIdx(idx);
			if (postContract.isValidPost(postId) && postContract.notPrivateOrIsFollower(postId, viewer)) {
				postContract.feedIncrViewCount(postId, viewer);
				posts[numPosts] = postStorageContract.getPost(postId);
				numPosts++;
			} 
			idx--;
		}

		// for next scroll, we start searching from this index
		storageContract.setScrollState(viewer, idx);

		return posts;
	}
}