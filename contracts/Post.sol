pragma solidity ^0.8.0;

import "./MediaNFT.sol";
import './Token.sol';
import "./RNG.sol";
import "./ContentModeration.sol";

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
		bool flagged;
		uint256 reportCount;
	}

	address owner;
	address userContractAddr;
	MediaNFT nftContract;
	Token tokenContract;
	RNG rngContract;
	// running number of post ids
	uint256 nextPostID = 0;
	// mapping of postID to the post structs
	mapping(uint256 => PostData) idToPost;
	// mapping for users to all of their posts (stored as an array of post ids)
	mapping(address => uint256[]) userToPosts;
	// keep track of who liked each post to ensure that there are no duplicate likes for this post (i.e an account cannot like a post twice)
	// it is a mapping of postID => user address => boolean value (true if user has liked this post)
	mapping(uint256 => mapping(address => bool)) hasLiked; 
	// keep track of who viewed each post to ensure that there are no duplicate views for this post (i.e an account can only increase the viewcount for a post at most once)
	// it is a mapping of postID => user address => boolean value (true if user has viewed this post)
	mapping(uint256 => mapping(address => bool)) hasViewed;
	uint256 MAX_REPORT_COUNT = 100;
	// keep track of who reported each post to ensure that there are no duplicate reports for this post (i.e an account can only increase the reportCount for a post at most once)
	// it is a mapping of postID => user address => boolean value (true if user has reported this post)
	mapping(uint256 => mapping(address => bool)) hasReported;
	// === END OF POST DATA STRUCTURES ===

	// === FEED DATA STRUCTURES ===
	// stores all posts (only storing the ids) to generate the feed for users
	// latest posts are always at the end of the array
	uint256[] globalFeed;
	// keep track of scroll states. 
	// scroll states tell us which post of the globalFeed did the user last scrolled until
	// this allow us to return the next N posts from the last-scrolled-until post
	mapping(address => uint256) scrollStates;
	uint256 POSTS_PER_SCROLL = 10;
	// === END OF FEED DATA STRUCTURES ===

	// === ADVERTISEMENT DATA STRUCTURES ===
	// struct for advertisement posts
	struct Ad {
		PostData postData;
		uint256 endTime;
	}
	// list of all of the current advertisements
	Ad[] ads;
	// the index at which to inject an advertisement on each scroll
	uint256 INSERT_AD_AT_IDX = POSTS_PER_SCROLL / 2;
	// keep track of view counts for current month.
	// this helps us to decide how to split the ad revenue amongst creators for this month.
	mapping(uint => uint) viewCountThisMonth;
	// we need this list to iterate through the keys in the above mapping in solidity. (cant iterate mapping in solidity)
	uint[] postsViewedThisMonth;
	address adContractAddr;
	// === END OF ADVERTISEMENT DATA STRUCTURES ===

	// === CONTENT MODERATION DATA STRUCTURES ===
	ContentModeration contentModerationContract;
	// === END OF CONTENT MODERATION DATA STRUCTURES ===
	
	constructor (RNG _rngContract, MediaNFT _nftContract, Token _tokenContract) {
		nftContract = _nftContract;
		tokenContract = _tokenContract;
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

	// a valid post is defined as a non-deleted & non-flagged post with a valid id
	modifier validId(uint256 id) { 
		require (id >= 0 && id < nextPostID, "invalid post id");
		_;
	}

	modifier notDeleted(uint256 id) {
		require(!idToPost[id].deleted, "post has been deleted");
		_;
	}

	modifier notFlagged(uint256 id) {
		require(!idToPost[id].flagged, "post has been flagged");
		_;
	}

	function canShowPost(uint256 id) private view validId(id) returns (bool) {
		PostData storage post = idToPost[id];
		return !post.deleted && !post.flagged;
	}

	// increments the view count for this post. 
	// we do not count duplicate views (i.e even if a user views a post multiple times, we count it as he only viewed it at most one time)
	// this reduces the chances of manipulation of viewcounts to gain ad revenue.
	// there are two view counts to maintain
	// 1. overall view count
	// 2. viewcount for this month, to calculate the ad revenue distribution for this monthly period
	function incrViewCount(uint256 id) private {
		// prevent duplicate counting of viewcount
		if (hasViewed[id][msg.sender]) {
			return;
		}

		idToPost[id].viewCount++;
		if (viewCountThisMonth[id] == 0) {
			// first time anyone has viewed this post this month
			postsViewedThisMonth.push(id);
		}
		viewCountThisMonth[id] += 1;

		hasViewed[id][msg.sender] = true;
	}

	// get post by post id. filters out deleted comments
	function getPost(uint256 id) public validId(id) notDeleted(id) notFlagged(id) returns (PostData memory)  {
		incrViewCount(id);
		PostData memory post = idToPost[id];

		// filter out deleted comments
		// we need to first find number of non deleted comments because we cannot allocate a dynamically sized memory array in soldiity
		uint256 numNonDeletedComments = 0;
		Comment[] memory comments = post.comments;
		for (uint256 i = 0; i < comments.length; i++) {
			if (!comments[i].deleted) {
				numNonDeletedComments++;
			} 
		}

		Comment[] memory filteredComments = new Comment[](numNonDeletedComments);
		uint idx = 0;
		for (uint256 i = 0; i < comments.length; i++) {
			if (!comments[i].deleted) {
				filteredComments[idx] = comments[i];
				idx++;
			} 
		}
		post.comments = filteredComments;

		return post;
	}

	// get multiple posts by multiple postids. filters out deleted & flagged posts and comments.
	function getPosts(uint256[] memory postIds) private returns (PostData[] memory) {
		// note that the length of the `posts` array is just an esimate of the true number of non-deleted posts
		// we need to give an estimated length because we cannot allocate a dynamically sized memory array in solidity (i.e an array without a specified length).
		PostData[] memory posts = new PostData[](postIds.length);
		// number of valid posts
		uint n = 0; 
		// find all valid posts
		for (uint i = 0; i < postIds.length; i++) {
			uint postId = postIds[i];
			if (canShowPost(postId)) {
				posts[n] = getPost(postId);
				n++;
			}
		}

		// copy over results to an array with exactly n elements.
		// this is so that we return an array with the correct number of elements (n).
		PostData[] memory postsResult = new PostData[](n);
		for (uint i = 0; i < n; i++) {
			postsResult[i] = posts[i];
		}

		return postsResult;
	}

	// returns all valid posts associated with this user (i.e post.owner == user)
	function getAllPostsByUser(address user) public returns (PostData[] memory) {
		uint256[] storage postIds = userToPosts[user];
		return getPosts(postIds);
	}

	// creates a post where the owner is msg.sender, caption is given as the first argument,
	// and ipfsCID is an optional field to indicate the media to associate with this post.
	// if ipfsCID is empty (i.e ipfsCID == ""), we take it as there is no media.
	// else if ipfsCID is non empty, we mint an nft to the user with the corresponding ipfsCID.

	// the function also adds the created post to the global feed.
	// the function returns the id of the created post
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

	// like the post specified by `id`. the liker is the `msg.sender`
	function like(uint256 id) public validId(id) notDeleted(id) notFlagged(id) {
		address liker = msg.sender;
		require(!hasLiked[id][liker], "you have already liked this post");
		hasLiked[id][liker] = true;
		idToPost[id].likes++;
	}

	// unlike the post specified by `id`. the liker is the `msg.sender`
	function unlike(uint256 id) public validId(id) notDeleted(id) notFlagged(id)  {
		address liker = msg.sender;
		require(hasLiked[id][liker], "you have not liked this post");
		hasLiked[id][liker] = false;
		idToPost[id].likes--;
	}

	// add a comment with `text` to post with id of `id`. the commentor is `msg.sender`.
	// returns the id of the comment
	function addComment(uint256 id, string memory text) public validId(id) notDeleted(id) notFlagged(id) returns (uint) {
		uint256 commentID = idToPost[id].comments.length;
		idToPost[id].comments.push(Comment(commentID, msg.sender, block.timestamp, text, false));
		return commentID;
	}

	// delete a comment with the specified postID and commentID.
	// the commentator is `msg.sender`. Only the owner of this comment can delete the comment.
	function deleteComment(uint256 postID, uint256 commentID) public validId(postID) notDeleted(postID) notFlagged(postID) {
		require(commentID >= 0 && commentID < idToPost[postID].comments.length, "invalid comment ID");
		Comment storage comment = idToPost[postID].comments[commentID];
		require(!comment.deleted, "comment is already deleted");
		require(comment.owner == msg.sender, "only owner of this comment can delete this comment");
		comment.deleted = true;
	}

	// delete the post specified by `id`. Only the owner of the post can delete the post.
	function deletePost(uint256 id) public postOwnerOnly(id) validId(id) notDeleted(id) {
		idToPost[id].deleted = true;
	}

	// report this post specified by `id`
	function reportPost(uint256 id) public validId(id) notDeleted(id) notFlagged(id) {
		require(!hasReported[id][msg.sender], "you have already reported this post");
		idToPost[id].reportCount++;
		hasReported[id][msg.sender] = true;
		if (idToPost[id].reportCount >= MAX_REPORT_COUNT) {
			idToPost[id].flagged = true;
		}
	}

	// get the tokenURI (i.e image link) to the NFT specified by `id`
	function getTokenURIByTokenID(uint id) public view returns (string memory) {
		return nftContract.tokenURI(id);
	}

	// get the tokenURI (i.e image link) to the NFT in the post specified by `id`
	function getTokenURIByPostID(uint id) public view validId(id) notDeleted(id) notFlagged(id) returns (string memory) {
		int tokenId = idToPost[id].mediaNFTID;
		require(tokenId >= 0, "this post does not have media");
		return getTokenURIByTokenID(uint(tokenId));
	}


	modifier userContractOnly() {
		require(msg.sender == userContractAddr, "user contract only");
		_;
	}

	function setUserContract(address _userContractAddr) public contractOwnerOnly {
		userContractAddr = _userContractAddr;
	}

	// delete all posts associated with `user`. this function is called by the User contract when deleting a user.
	// the tx.origin must be the same address as `user`.
	function deleteAllUserPosts(address user) external userContractOnly {
		require (tx.origin == user, "only the specified user can initiate this action");
		uint256[] storage posts = userToPosts[user];
		for (uint i = 0; i < posts.length; i++) {
			uint256 postId = posts[i];
			idToPost[postId].deleted = true;
		}
	}

	function getOwner(uint256 id) public view returns (address) {
		return idToPost[id].owner;
	}

	function getFlaggedStatus(uint256 id) public view returns (bool) {
		return idToPost[id].flagged;
	}
	// === POST CRUD OPERATIONS ===

	// === FEED OPERATIONS ===
	// adds this post to the global feed
	function addToFeed(uint256 postId) private {
		globalFeed.push(postId);
	}

	// initializes the start of a scroll.
	// this returns the latest N posts, where N=POSTS_PER_SCROLL specified at the start of this contract
	function startScroll() public returns (PostData[] memory) {
		// start idx = last element of array (where the lastest post is at)
		return scrollPosts(globalFeed.length - 1);
	}

	// continues the scroll.
	// this returns the next N posts, starting from where the user last left off, as captured by the `scrollStates` mapping
	function continueScroll() public returns (PostData[] memory) {
		// start idx = the latest post which the user has not seen according to `scrollStates`
		return scrollPosts(scrollStates[msg.sender]);
	}

	// return the next 10 (non-deleted && non-flagged) posts starting from startIdx.
	// note that we count from the end of array to start of array, as the latest posts are the end of the array.
	function scrollPosts(uint startIdx) private returns (PostData[] memory) {
		require(startIdx >= 0 && globalFeed.length > 0 , "no more posts to scroll");

		uint numPosts = 0;
		uint idx = startIdx;
		PostData[] memory posts = new PostData[](POSTS_PER_SCROLL);
		// add up to `POSTS_PER_SCROLL` posts to result, or until there is no more posts from global feed to return (i.e idx < 0)
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
			if (canShowPost(postId)) {
				posts[numPosts] = getPost(postId);
				numPosts++;
			} 
			idx--;
		}

		// for next scroll, we start searching from this index
		scrollStates[msg.sender] = idx; 

		return posts;
	}
	// === END OF FEED OPERATIONS ===

	// === ADVERTISMENT OPERATIONS ===
	modifier AdContractOnly {
		require(msg.sender == adContractAddr, "only ad contract can execute this function");
		_;
	}

	function setAdContract(address _adContract) public contractOwnerOnly {
		adContractAddr = _adContract;
	}

	// similar to createPost, but in stead of adding to the global feed, we add to the ads array.
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
			// check if this ad is expired or is somehow flagged/deleted
			if (ads[randIdx].endTime < block.timestamp || !canShowPost(ads[randIdx].postData.id)) {
				// delete this invalid ad by..
 				// firstly, replace this expired ad with the ad at the last idx
				ads[randIdx] = ads[n - 1];
				// secondly, delete the last idx
				ads.pop(); 
			} else {
				// this ad is valid, return this ad!
				return (ads[randIdx], true);
			}
		}

		Ad memory emptyAd; // we have to return this because solidity does not have null values..
		return (emptyAd, false);
	}

	// calculates the distribution of ad revenue to creators for the current month according to viewcount
	// returns the following: (creators, viewCount, totalViewCount) where
	// 1. payee[i] is the creator who will receive ad payouts
	// 2. viewCount[i] is the number of views payee[i] got in this month.
	function getAdRevenueDistribution() public view AdContractOnly returns (address[] memory, uint[] memory, uint) {
		uint numCreators = 0;
		uint totalViewCount = 0;
		 // note we are just estimating the number of creators here through postsViewedThisMonth.length
		address[] memory creators = new address[](postsViewedThisMonth.length);
		uint[] memory viewCounts = new uint[](postsViewedThisMonth.length);

		// we are doing four things in this loop.
		// 1. we are finding an index j to put a creator in the `creators` array. the `creators` array does not have duplicate elements.
		// 2. we are finding the number of distinct creators to get ads revenue payout this month. (numCreators)
		// 3. we are finding the total number of viewcounta for each creator.
		// 4. we are counting the total number of viewcounts for this month.
		for (uint i = 0; i < postsViewedThisMonth.length; i++) {
			uint postId = postsViewedThisMonth[i];
			PostData storage post = idToPost[postId];
			address creator = post.owner;

			// find an index j for this `creator` (iterate through the array until we find an empty slot to insert (i.e address(0)) or a duplicate entry of 'creator')
			uint j = 0;
			while (creators[j] != address(0) && creators[j] != creator) j++;
			if (creators[j] != creator) {
				// if we have not inserted this creator, insert it.
				creators[j] = creator;
				numCreators++;
			}

			totalViewCount += post.viewCount;
			viewCounts[j] += post.viewCount;
		}

		// copy over the exact number of creators & viewcounts (previously, we were using an estimated number of creators to create the arrays)
		address[] memory payeesResult = new address[](numCreators);
		uint[] memory viewCountsResult = new uint[](numCreators);
		for (uint i = 0; i < numCreators; i++) {
			payeesResult[i] = creators[i];
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

	// === CONTENT MODERATION OPERATIONS === 
	modifier ContentModerationContractOnly {
		require(msg.sender == address(contentModerationContract), "only content moderation contract can execute this function");
		_;
	}

	function setContentModerationContract(ContentModeration _contentModerationContract) public contractOwnerOnly {
		contentModerationContract = _contentModerationContract;
	}

	function resetFlagAndReportCount(uint postId) public ContentModerationContractOnly {
		idToPost[postId].flagged = false;
		idToPost[postId].reportCount = 0;
	}

	// users can call this function to get a flagged post which has a dispute open.
	// they can only view the post corresponding to the dispute they are voting for.
	function getPostToReviewDispute(uint id) public view validId(id) notDeleted(id) returns (PostData memory) {
		require(contentModerationContract.getCurrentDisputeOfUser(msg.sender) == id, "you are not voting for the specified dispute id");
		PostData memory post = idToPost[id];

		// filter out deleted comments
		// we need to first find number of non deleted comments because we cannot allocate a dynamically sized memory array in soldiity
		uint256 numNonDeletedComments = 0;
		Comment[] memory comments = post.comments;
		for (uint256 i = 0; i < comments.length; i++) {
			if (!comments[i].deleted) {
				numNonDeletedComments++;
			} 
		}

		Comment[] memory filteredComments = new Comment[](numNonDeletedComments);
		uint idx = 0;
		for (uint256 i = 0; i < comments.length; i++) {
			if (!comments[i].deleted) {
				filteredComments[idx] = comments[i];
				idx++;
			} 
		}
		post.comments = filteredComments;

		return post;
	}
	// === END OF CONTENT MODERATION OPERATIONS === 
}

