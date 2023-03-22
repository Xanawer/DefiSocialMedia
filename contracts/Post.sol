pragma solidity ^0.8.0;

import "./MediaNFT.sol";
import './Token.sol';
import "./RNG.sol";
import "./ContentModeration.sol";
import "./User.sol";
import "./Feed.sol";

contract Post {
	// === POST DATA STRUCTURES ===
	struct Comment {
		uint256 id;
		address owner;
		uint256 timestamp;
		string text;
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
	User userContract;
	MediaNFT nftContract;
	Token tokenContract;
	RNG rngContract;
	Feed feedContract;
	// running number of post ids
	uint256 nextPostID = 0;
	// mapping of postID to the post structs
	mapping(uint256 => PostData) idToPost;
	// mapping for users to all of their posts (stored as an array of post ids)
	mapping(address => uint256[]) userToPosts;
	// keep track of who liked each post to ensure that there are no duplicate likes for this post (i.e an account cannot like a post twice)
	// it is a mapping of postID => user address => boolean value (true if user has liked this post)
	mapping(uint256 => mapping(address => bool)) hasLiked; 
	// keep track of who viewed each post at what time to reduce the chance of bot views  (an account can only increase the viewcount for a post at most once per day)
	// it is a mapping of postID => user address => last viewed time
	mapping(uint256 => mapping(address => uint256)) lastViewed;
	// the duration of which a view count will not be double counted
	uint256 VIEWCOUNT_COOLDOWN = 1 days;
	// keep track of who reported each post to ensure that there are no duplicate reports for this post (i.e an account can only increase the reportCount for a post at most once)
	// it is a mapping of postID => user address => boolean value (true if user has reported this post)
	mapping(uint256 => mapping(address => bool)) hasReported;
	uint256 MAX_REPORT_COUNT = 100;
	// === END OF POST DATA STRUCTURES ===

	// === ADVERTISEMENT DATA STRUCTURES ===
	// struct for advertisement posts
	struct Ad {
		PostData postData;
		uint256 endTime;
	}
	// list of all of the current advertisements
	Ad[] ads;
	// creators to pay out ad revneue for this month
	address[] payeesThisMonth;
	// viewCountThisMonth[i] correspond to the viewcount for creator in payeesThisMonth[i]
	uint[] viewCountThisMonth;
	// track the index where creator is stored in the `payeesThisMonth` array
	mapping(address => uint) creatorToIdx;
	// overall total view count for this month
	uint totalViewCountThisMonth;
	address adContractAddr;
	// === END OF ADVERTISEMENT DATA STRUCTURES ===

	// === CONTENT MODERATION DATA STRUCTURES ===
	ContentModeration contentModerationContract;
	// === END OF CONTENT MODERATION DATA STRUCTURES ===

	// === EVENTS ===
	event PostCreated(address creator, uint postID, uint256 timePosted);
	event PostLiked(address UserLiked, uint postID);
	event PostUnliked(address UserUnliked, uint postID);
	event Commented(address commentor, uint postID, string comment);
	event PostDeleted(address creator, uint postID, uint256 timeDeleted);
	event CommentDeleted(address commentor, uint postID, uint256 timeDeleted);
	
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

	modifier userExists(address user) {
		require(userContract.existsAndNotDeleted(user), "user does not exist");
		_;
	}

	// a viewer can view a creator post if the creator account is not private, or it is private and the viewer is a follower
	function canViewCreatorPosts(address creator, address viewer) public view returns (bool) {
		return !userContract.isPrivateAccount(creator) || userContract.isFollower(creator, viewer);
	}

	function notDeletedOrFlagged(uint256 id) public view validId(id) returns (bool) {
		PostData storage post = idToPost[id];
		return !post.deleted && !post.flagged;
	}

	// increments the view count for this post. 
	// we do not count duplicate views within a day (i.e even if a user views a post multiple times in 1 day, we count it as he only viewed it at most one time)
	// this reduces the chances of manipulation of viewcounts to gain ad revenue.
	// there are two view counts to maintain
	// 1. overall view count
	// 2. viewcount for this month, to calculate the ad revenue distribution for this monthly period
	function incrViewCount(uint256 id) private {
		// prevent duplicate counting of viewcount
		if (block.timestamp - lastViewed[id][tx.origin] < VIEWCOUNT_COOLDOWN) {
			// if the time between now and last viewed is less than 1 day, we do not double count.
			return;
		}

		// overall view count
		idToPost[id].viewCount++;

		// viewcount for this month
		// creator of this post
		address creator = idToPost[id].owner;
		// idx of this creator in the `payeesThisMonth` array
		uint idx = creatorToIdx[creator];
		// check if we are already tracking this creator (i.e the creator at `payeesThisMonth[idx]` is really the creator)
		bool creatorAlreadyTracked = idx < payeesThisMonth.length && payeesThisMonth[idx] == creator;
		if (!creatorAlreadyTracked) {
			// this creator has not been tracked this month, add it to the end of the array and track the index of where it was stored
			idx = payeesThisMonth.length;
			creatorToIdx[creator] = idx;
			payeesThisMonth.push(creator);
			viewCountThisMonth.push(0);
		}
		// increment viewcounts for this month
		viewCountThisMonth[idx]++;
		totalViewCountThisMonth;

		lastViewed[id][tx.origin] = block.timestamp;
	}

	// get post by post id. filters out deleted comments
	function getPost(uint256 id) public validId(id) notDeleted(id) notFlagged(id) returns (PostData memory)  {
		PostData memory post = idToPost[id];
		require(canViewCreatorPosts(post.owner, tx.origin), "the user is private, and you are not in the following list");
		incrViewCount(id);
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
			if (notDeletedOrFlagged(postId) && canViewCreatorPosts(idToPost[postId].owner, tx.origin)) {
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
		require(canViewCreatorPosts(user, tx.origin), "the user is private, and you are not in the following list");
		uint256[] storage postIds = userToPosts[user];
		return getPosts(postIds);
	}

	// creates a post where the owner is msg.sender, caption is given as the first argument,
	// and ipfsCID is an optional field to indicate the media to associate with this post.
	// if ipfsCID is empty (i.e ipfsCID == ""), we take it as there is no media.
	// else if ipfsCID is non empty, we mint an nft to the user with the corresponding ipfsCID.

	// the function also adds the created post to the global feed.
	// the function returns the id of the created post
	function createPost(string memory caption, string memory ipfsCID) public userExists(msg.sender) returns (uint) {
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
		feedContract.addToFeed(post.id);
		
		emit PostCreated(msg.sender, post.id, block.timestamp);
		return post.id;
	}

	// like the post specified by `id`. the liker is the `msg.sender`
	function like(uint256 id) public validId(id) notDeleted(id) notFlagged(id) userExists(msg.sender) {
		require(canViewCreatorPosts(idToPost[id].owner, tx.origin), "the user is private, and you are not in the following list");
		address liker = msg.sender;
		require(!hasLiked[id][liker], "you have already liked this post");
		hasLiked[id][liker] = true;
		idToPost[id].likes++;
		emit PostLiked(msg.sender, id);
	}

	// unlike the post specified by `id`. the liker is the `msg.sender`
	function unlike(uint256 id) public validId(id) notDeleted(id) notFlagged(id) {
		require(canViewCreatorPosts(idToPost[id].owner, tx.origin), "the user is private, and you are not in the following list");
		address liker = msg.sender;
		require(hasLiked[id][liker], "you have not liked this post");
		hasLiked[id][liker] = false;
		idToPost[id].likes--;
		emit PostUnliked(msg.sender, id);
	}

	// add a comment with `text` to post with id of `id`. the commentor is `msg.sender`.
	// returns the id of the comment
	function addComment(uint256 id, string memory text) public validId(id) notDeleted(id) notFlagged(id) userExists(msg.sender) returns (uint) {
		require(canViewCreatorPosts(idToPost[id].owner, tx.origin), "the user is private, and you are not in the following list");
		uint256 commentID = idToPost[id].comments.length;
		idToPost[id].comments.push(Comment(commentID, msg.sender, block.timestamp, text));
		emit Commented(msg.sender, id, text);
		return commentID;
	}

	// delete a comment with the specified postID and commentID.
	// the commentator is `msg.sender`. Only the owner of this comment can delete the comment.
	function deleteComment(uint256 postID, uint256 commentID) public validId(postID) notDeleted(postID) notFlagged(postID) {
		require(canViewCreatorPosts(idToPost[postID].owner, tx.origin), "the user is private, and you are not in the following list");		
		require(commentID >= 0 && commentID < idToPost[postID].comments.length, "invalid comment ID");
		Comment[] storage comments = idToPost[postID].comments;
		for (uint i = 0; i < comments.length; i++) {
			if (comments[i].id == commentID) {
				require(comments[i].owner == msg.sender, "only owner of this comment can delete this comment");
				// delete this comment
				comments[i] = comments[comments.length - 1];
				comments.pop();
				emit CommentDeleted(msg.sender, postID, block.timestamp);
				return;
			}
		}
		require(false, "cannot find comment");
	}

	// delete the post specified by `id`. Only the owner of the post can delete the post.
	function deletePost(uint256 id) public postOwnerOnly(id) validId(id) notDeleted(id) {
		idToPost[id].deleted = true;
		emit PostDeleted(msg.sender, id, block.timestamp);
	}

	// report this post specified by `id`
	function reportPost(uint256 id) public validId(id) notDeleted(id) notFlagged(id) userExists(msg.sender) {
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
		require(canViewCreatorPosts(idToPost[id].owner, tx.origin), "the user is private, and you are not in the following list");		
		int tokenId = idToPost[id].mediaNFTID;
		require(tokenId >= 0, "this post does not have media");
		return getTokenURIByTokenID(uint(tokenId));
	}


	modifier userContractOnly() {
		require(msg.sender == address(userContract), "user contract only");
		_;
	}

	function setUserContract(User _userContract) public contractOwnerOnly {
		userContract = _userContract;
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

	// === ADVERTISMENT OPERATIONS ===
	modifier AdContractOnly {
		require(msg.sender == adContractAddr, "only ad contract can execute this function");
		_;
	}

	function setAdContract(address _adContract) public contractOwnerOnly {
		adContractAddr = _adContract;
	}

	// similar to createPost, but in stead of adding to the global feed, we add to the ads array.
	function createAd(address user, string memory caption, string memory ipfsCID, uint endTime) public AdContractOnly returns (uint) {
		// default value of -1 indicates this post does not have any media attached to it
		int mediaNFTID = -1;
		// if this post has a media (i.e cid parameter is non empty)
		if (bytes(ipfsCID).length > 0) { // same as ipfsCID != "", but cant do that in solidity
			// mint nft to user
			mediaNFTID = int(nftContract.mint(user, ipfsCID));
		}

		Ad storage ad = ads.push();
		ad.endTime = endTime;

		PostData storage post = ad.postData;
		post.id = nextPostID;
		post.owner = user;
		post.caption = caption;
		post.likes = 0;
		post.timestamp = block.timestamp;
		post.viewCount = 0;
		post.mediaNFTID = mediaNFTID;
		post.deleted = false; 
		
		userToPosts[user].push(post.id);
		idToPost[post.id] = post;
		nextPostID++;
		
		return post.id;
	}

	// choose an advertisement uniformly at random so that each ad gets an equal chance 
	// returns a tuple (ad, found), where ad is the advertisement to return, and found is a bool indicating if we successfully found an ad
	function getAd() public returns (Ad memory, bool) {
		while (ads.length > 0) {
			uint n = ads.length;	
			uint randIdx = rngContract.random() % n;
			// check if this ad is expired or is somehow flagged/deleted
			if (ads[randIdx].endTime < block.timestamp || !notDeletedOrFlagged(ads[randIdx].postData.id)) {
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
	// returns the following: (creators, viewCount, totalViewCountThisMonth) where
	// 1. payee[i] is the creator who will receive ad payouts
	// 2. viewCount[i] is the number of views payee[i] got in this month.
	function getAdRevenueDistribution() public view AdContractOnly returns (address[] memory, uint[] memory, uint) {
		return (payeesThisMonth, viewCountThisMonth, totalViewCountThisMonth);
	}

	// resets the monthly tracker for view counts
	function resetMonthlyViewCounts() public AdContractOnly {
		delete payeesThisMonth;
		delete viewCountThisMonth;
		totalViewCountThisMonth = 0;
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
	function getPostToReviewDispute(uint postId, uint disputeId) public view validId(postId) notDeleted(postId) returns (PostData memory) {
		require(contentModerationContract.getCurrentDisputeIdOfUser(msg.sender) == disputeId, "you are not voting for the specified dispute id");
		PostData memory post = idToPost[postId];
		return post;
	}
	// === END OF CONTENT MODERATION OPERATIONS === 

	function setFeedContract(Feed _feedContract) public contractOwnerOnly {
		feedContract = _feedContract;
	}
}

