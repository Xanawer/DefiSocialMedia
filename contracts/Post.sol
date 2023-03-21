pragma solidity ^0.8.0;

import "./MediaNFT.sol";
import './Token.sol';
import "./RNG.sol";

contract Post {
	// === POST DATA STRUCTURES ===
	struct Comment {
		uint256 id;
		address owner;
		uint256 timestamp;
		string text;
		bool deleted;
	}

	struct PostData {
		uint256 id;
		address owner;
		string caption;
		uint256 likes;
		Comment[] comments;
		uint256 timestamp;
		uint256 viewCount;
		int mediaNFTID; // value of -1 dictates no media
		bool deleted;
	}

	address owner;
	MediaNFT nftContract;
	Token tokenContract;
	RNG rngContract;
	uint256 nextPostID = 0;
	mapping(uint256 => PostData) idToPost;
	// keep track of who liked each post to ensure that there are no duplicate likes for this post (i.e an account cannot like a post twice)
	mapping(uint256 => mapping(address => bool)) hasLiked; 
	// keep track of who viewed each post to ensure that there are no duplicate views for this post (i.e an account can only increase the viewcount for a post at most once)
	mapping(uint256 => mapping(address => bool)) hasViewed;
	// mapping for users to his/her post ids
	mapping(address => uint256[]) userToPosts;
	// === END OF POST DATA STRUCTURES ===

	// === FEED DATA STRUCTURES ===
	// latest posts are always at the end of the array
	uint256[] globalFeed;
	// keep track of scroll states. default value of 0 indicates the scroll state is not started
	mapping(address => uint256) scrollStates;
	uint256 POSTS_PER_SCROLL = 10;
	// === END OF FEED DATA STRUCTURES ===

	// === ADVERTISEMENT DATA STRUCTURES ===
	struct Ad {
		PostData postData;
		uint256 endTime;
	}
	Ad[] ads;
	uint256 INSERT_AD_AT_IDX = POSTS_PER_SCROLL / 2;
	// keep track of view counts for current month.
	// this helps us to decide how to split the ad revenue amongst payees
	mapping(uint => uint) viewCountThisMonth;
	// we need this list to iterate through the map in solidity..
	uint[] postsViewedThisMonth;
	address adContract;
	// === END OF ADVERTISEMENT DATA STRUCTURES ===

	constructor (RNG _rngContract) {
		nftContract = new MediaNFT();
		tokenContract = new Token();
		rngContract = _rngContract;
		owner = msg.sender;
	}

	modifier contractOwnerOnly() {
		require(msg.sender == owner, "contract owner only function");
		_;
	}

	// === POST CRUD OPERATIONS ===
	modifier postOwnerOnly(uint256 id) {
		require(msg.sender == idToPost[id].owner, "only owner of post can do this action");
		_;
	}

	// a valid post is defined as a non-deleted post with a valid id
	modifier validPost(uint256 id) { 
		require (id >= 0 && id < nextPostID, "invalid post id");
		require(!idToPost[id].deleted, "post has been deleted");
		_;
	}

	function incrViewCount(uint256 id) private {
		// prevent duplicate counting of viewcount
		if (hasViewed[id][msg.sender]) {
			return;
		}

		idToPost[id].viewCount++;
		if (viewCountThisMonth[id] == 0) {
			// first time viewing this post
			postsViewedThisMonth.push(id);
		}
		viewCountThisMonth[id] += 1;

		hasViewed[id][msg.sender] = true;
	}

	function getPost(uint256 id) public validPost(id) returns (PostData memory)  {
		incrViewCount(id);
		PostData memory post = idToPost[id];
		// filter out deleted comments
		Comment[] memory comments = post.comments;
		for (uint256 i = 0; i < comments.length; i++) {
			if (comments[i].deleted) {
				delete comments[i];
				comments[i].deleted = true;
			}
		}
		return post;
	}

	function getPosts(uint256[] memory postIds) public returns (PostData[] memory) {
		uint256 notDeletedCount = 0;
		// get number of non deleted posts 
		// this is because we cannot allocate a dynamically sized memory array in solidity 
		for (uint i = 0; i < postIds.length; i++) {
			uint postId = postIds[i];
			if (!idToPost[postId].deleted) {
				notDeletedCount++;
			}
		}

		PostData[] memory posts = new PostData[](notDeletedCount);
		uint idx = 0;
		for (uint i = 0; i < postIds.length; i++) {
			uint postId = postIds[i];
			if (!idToPost[postId].deleted) {
				posts[idx] = getPost(postId);
				idx++;
			}
		}

		return posts;
	}

	function getAllPostsByUser(address user) public returns (PostData[] memory) {
		uint256[] storage postIds = userToPosts[user];
		return getPosts(postIds);
	}

	// returns id of post created
	function createPost(string memory caption, string memory ipfsCID) public returns (uint) {
		// default value of -1 indicates this post does not have any media attached to it
		int mediaNFTID = -1;
		// if this post has a media (i.e cid parameter is non empty)
		if (bytes(ipfsCID).length > 0) { // same as ipfsCID != "", but cant do that in solidity
			// mint nft to user
			mediaNFTID = int(nftContract.mint(msg.sender, ipfsCID));
		}
		PostData storage post = idToPost[nextPostID];

		post.id = nextPostID;
		post.owner = msg.sender;
		post.caption = caption;
		post.likes = 0;
		post.timestamp = block.timestamp;
		post.viewCount = 0;
		post.mediaNFTID = mediaNFTID;
		post.deleted = false; 
		
		nextPostID++;
		userToPosts[msg.sender].push(post.id);
		addToFeed(post.id);
		
		return post.id;
	}

	function like(uint256 id) public validPost(id) {
		address liker = msg.sender;
		require(!hasLiked[id][liker], "you have already liked this post");
		hasLiked[id][liker] = true;
		idToPost[id].likes++;
	}

	function unlike(uint256 id) public validPost(id) {
		address liker = msg.sender;
		require(hasLiked[id][liker], "you have not liked this post");
		hasLiked[id][liker] = false;
		idToPost[id].likes--;
	}

	function addComment(uint256 id, string memory text) public validPost(id) {
		uint256 commentID = idToPost[id].comments.length;
		idToPost[id].comments.push(Comment(commentID, msg.sender, block.timestamp, text, false));
	}

	function deleteComment(uint256 postID, uint256 commentID) public validPost(postID) {
		require(commentID >= 0 && commentID < idToPost[postID].comments.length, "invalid comment ID");
		Comment storage comment = idToPost[postID].comments[commentID];
		require(!comment.deleted, "comment is already deleted");
		require(comment.owner == msg.sender, "only owner of this comment can delete this comment");
		comment.deleted = true;
	}

	function deletePost(uint256 id) public postOwnerOnly(id) validPost(id) {
		idToPost[id].deleted = true;
	}

	function getTokenURIByTokenID(uint id) public view returns (string memory) {
		return nftContract.tokenURI(id);
	}

	function getTokenURIByPostID(uint id) public view validPost(id) returns (string memory) {
		int tokenId = idToPost[id].mediaNFTID;
		require(tokenId >= 0, "this post does not have media");
		return getTokenURIByTokenID(uint(tokenId));
	}

	function deleteAllUserPosts(address user) public {
		require (tx.origin == user, "only the specified user can initiate this action");
		uint256[] storage posts = userToPosts[user];
		for (uint i = 0; i < posts.length; i++) {
			uint256 postId = posts[i];
			delete idToPost[postId];
		}
		delete userToPosts[user];
	}
	// === POST CRUD OPERATIONS ===

	// === FEED OPERATIONS ===
	function addToFeed(uint256 postId) private {
		globalFeed.push(postId);
	}

	function startScroll() public returns (PostData[] memory) {
		return scrollPosts(globalFeed.length - 1);
	}

	function continueScroll() public returns (PostData[] memory) {
		return scrollPosts(scrollStates[msg.sender]);
	}

	// return the next 10 (non-deleted) posts starting from startIdx.
	// note that we count from the end of array to start of array,
	// as the latest posts are the end of the array.
	function scrollPosts(uint startIdx) private returns (PostData[] memory) {
		if (startIdx < 0 || globalFeed.length == 0) {
			delete scrollStates[msg.sender];
			require(false, "no more posts to scroll");
		}

		if (startIdx + 1 <= POSTS_PER_SCROLL) {
			return getPosts(globalFeed);
		}

		uint numPosts = 0;
		uint idx = startIdx;
		PostData[] memory posts = new PostData[](POSTS_PER_SCROLL);
		while (numPosts < POSTS_PER_SCROLL && idx >= 0) {
			// ADVERTISMENT INJECTION
			if (numPosts == INSERT_AD_AT_IDX) {
				bool found;
				Ad memory ad;
				(ad, found) = getAd();
				if (found) {
					posts[numPosts] = ad.postData;
					numPosts++;
					continue;
				}
				// if we cannot find an ad.. continue adding more posts from global feed
			}

			uint postId = globalFeed[idx];
			if (!idToPost[postId].deleted) {
				posts[numPosts] = getPost(postId);
				numPosts++;
			} 
			idx--;
		}

		// next scroll, we start searching from this index
		scrollStates[msg.sender] = idx; 

		return posts;
	}
	// === END OF FEED OPERATIONS ===

	// === ADVERTISMENT OPERATIONS ===
	modifier AdContractOnly {
		require(msg.sender == adContract, "only ad contract can execute this function");
		_;
	}

	function setAdContract(address _adContract) public contractOwnerOnly {
		adContract = _adContract;
	}

	function createAd(string memory caption, string memory ipfsCID, uint endTime) public AdContractOnly returns (uint) {
		// default value of -1 indicates this post does not have any media attached to it
		int mediaNFTID = -1;
		// if this post has a media (i.e cid parameter is non empty)
		if (bytes(ipfsCID).length > 0) { // same as ipfsCID != "", but cant do that in solidity
			// mint nft to user
			mediaNFTID = int(nftContract.mint(msg.sender, ipfsCID));
		}

		Ad storage ad = ads.push();
		ad.endTime = endTime;
		PostData storage post = ad.postData;

		post.id = nextPostID;
		post.owner = msg.sender;
		post.caption = caption;
		post.likes = 0;
		post.timestamp = block.timestamp;
		post.viewCount = 0;
		post.mediaNFTID = mediaNFTID;
		post.deleted = false; 
		
		userToPosts[msg.sender].push(post.id);
		idToPost[post.id] = post;
		nextPostID++;
		
		return post.id;
	}

	// choose an advertisement uniformly at random so that each ad gets an equal chance 
	// returns a tuple (ad, found), where ad is the advertisement to return, and found is a bool indicating if we successfully found an ad
	function getAd() private returns (Ad memory, bool) {
		while (ads.length > 0) {
			uint n = ads.length;	
			uint randIdx = rngContract.random() % n;
			// check if this ad is expired
			if (ads[randIdx].endTime < block.timestamp) {
				// delete this expired ad
				ads[randIdx] = ads[n - 1]; // replace this expired ad with the ad at the last idx
				ads.pop(); // delete the last idx
			} else {
				// this ad is not expired, return this ad!
				return (ads[randIdx], true);
			}
		}

		Ad memory emptyAd; // we have to return this because solidity does not have null values..
		return (emptyAd, false);
	}

	// calculates the distribution of ad revenue to payees for the current month according to viewcount
	// returns the following: (payees, viewCount, totalViewCount) where
	// 1. payee[i] is the creator who will receive ad payouts
	// 2. viewCount[i] is the number of views payee[i] got in this month.
	function getAdRevenueDistribution() public view AdContractOnly returns (address[] memory, uint[] memory, uint) {
		uint numCreators = 0;
		uint totalViewCount = 0;
		 // note we are just estimating the number of payees here through postsViewedThisMonth.length
		address[] memory payees = new address[](postsViewedThisMonth.length);
		uint[] memory viewCounts = new uint[](postsViewedThisMonth.length);
		// get number of payees
		// we need to do this because we cannot allocate dynamically sized memory arrays in solidity for the payee array.
		for (uint i = 0; i < postsViewedThisMonth.length; i++) {
			uint postId = postsViewedThisMonth[i];
			PostData storage post = idToPost[postId];
			address creator = post.owner;
			// check if we have already inserted this creator (iterate through the array until we find an empty slot (i.e address(0)) or a duplicate entry of 'creator')
			uint j = 0;
			while (payees[j] != address(0) && payees[j] != creator) j++;
			if (payees[j] != creator) {
				// if we have not inserted this creator, insert it.
				payees[j] = creator;
				numCreators++;
			}

			totalViewCount += post.viewCount;
			viewCounts[j] += post.viewCount;
		}

		// copy over the exact number of payees & viewcounts (previously, we were using an estimated number of creators to create the arrays)
		address[] memory payeesResult = new address[](numCreators);
		uint[] memory viewCountsResult = new uint[](numCreators);
		for (uint i = 0; i < numCreators; i++) {
			payeesResult[i] = payees[i];
			viewCountsResult[i] = viewCounts[i];
		}

		return (payeesResult, viewCountsResult, totalViewCount);
	}

	// resets the monthly tracker for view counts
	function resetMonthlyViewCounts() public AdContractOnly {
		// delete mapping
		for (uint i = 0; i < postsViewedThisMonth.length; i++) {
			uint postId = postsViewedThisMonth[i];
			delete viewCountThisMonth[postId];
		}
		
		// reset array
		delete postsViewedThisMonth;
	}
	// === END OF ADVERTISMENT OPERATIONS ===
}

