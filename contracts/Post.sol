pragma solidity ^0.8.0;

import "./NFT.sol";
import './Token.sol';
import "./RNG.sol";
import "./ContentModeration.sol";
import "./PostStorage.sol";
import "./User.sol";	
import "./Feed.sol";

contract Post{
	address owner;

	PostStorage storageContract;
	User userContract;
	NFT nftContract;
	Token tokenContract;
	RNG rngContract;
	Feed feedContract;
	ContentModeration contentModerationContract;	
	address adContractAddr;	

	// the duration of which a view count will not be double counted
	uint256 VIEWCOUNT_COOLDOWN = 1 days;	
	uint256 MAX_REPORT_COUNT = 100;	

	// === EVENTS ===
	event PostCreated(address creator, uint postId, uint256 timePosted);
	event PostLiked(address UserLiked, uint postId);
	event PostUnliked(address UserUnliked, uint postId);
	event PostDeleted(address creator, uint postId, uint256 timeDeleted);
	event Commented(address commentor, uint postId, uint commentId, string comment);
	event CommentDeleted(address commentor, uint postId, uint commentId, uint256 timeDeleted);	

	constructor (RNG _rngContract, NFT _nftContract, Token _tokenContract, PostStorage _storageContract) {
		nftContract = _nftContract;
		tokenContract = _tokenContract;
		rngContract = _rngContract;
		storageContract = _storageContract;
		owner = msg.sender;
	}	

	function init(User _userContract, Feed _feedContract, address _adContractAddr, ContentModeration _contentModerationContract) public contractOwnerOnly {
		setUserContract(_userContract);
		setFeedContract(_feedContract);
		setAdContract(_adContractAddr);
		setContentModerationContract(_contentModerationContract);
	}	

	modifier contractOwnerOnly() {
		require(msg.sender == owner, "contract owner only function");
		_;
	}

	// === POST CRUD OPERATIONS ===
	modifier creatorOnly(uint256 id) {
		address creator = msg.sender;
		require(isCreatorOf(id, creator), "only creator of post can do this action");
		_;
	}

	// a valid post is defined as a non-deleted & non-flagged post with a valid id
	modifier exists(uint256 id) { 
		require(storageContract.postExists(id), "invalid post id");
		_;
	}

	modifier notDeleted(uint256 id) {
		require(!storageContract.isDeleted(id), "post has been deleted");
		_;
	}

	modifier notFlagged(uint256 id) {
		require(!storageContract.isFlagged(id), "post has been flagged");
		_;
	}

	modifier canAccess(uint id, address viewer) {
		require(storageContract.postExists(id), "invalid post id");
		require(!storageContract.isDeleted(id), "post has been deleted");	
		require(!storageContract.isFlagged(id), "post has been flagged");
		require(notPrivateOrIsFollower(id, viewer), "the user is private, and you are not in the following list");					
		_;
	}

	modifier validUser(address user) {
		require(userContract.validUser(user), "user does not exist");
		_;
	}

	function viewPost(uint id) public canAccess(id, msg.sender) returns (PostStorage.Post memory) {
		address viewer = msg.sender;
		incrViewCount(id, viewer);
		return storageContract.getPost(id);
	}

	function viewAllPostsByCreator(address creator) public returns (PostStorage.Post[] memory) {
		uint[] memory postIds = userContract.getAllPostIdsByUser(creator);
		uint n = countValidPosts(postIds);
		PostStorage.Post[] memory filtered = new PostStorage.Post[](n);
		uint idx = 0;

		for (uint i = 0; i < postIds.length; i++) {
			uint postId = postIds[i];
			if (isValidPost(postId)) {
				filtered[idx] = viewPost(postId);
				idx++;
			}
		}

		return filtered;
	}

	function countValidPosts(uint[] memory posts) private view returns (uint) {
		uint count = 0;
		for (uint i = 0; i < posts.length; i++) {
			if (isValidPost(posts[i])) {
				count++;
			}
		}
		return count;
	}

	function createPost(string memory caption, string memory ipfsCID) public validUser(msg.sender) returns (uint) {
		address creator = msg.sender;

		uint nftID = mintNFT(creator, ipfsCID);
		uint id = storageContract.createPost(creator, caption, nftID);
		feedContract.addToFeed(id);
		userContract.newPost(creator, id);

		emit PostCreated(creator, id, block.timestamp);
		return id;
	}

	function mintNFT(address creator, string memory ipfsCID) private returns (uint) {
		uint nftID = 0;
		// if this post has a media (i.e cid parameter is non empty)
		if (bytes(ipfsCID).length > 0) { // same as ipfsCID != "", but cant do that in solidity
			// mint nft to user
			nftID = nftContract.mint(creator, ipfsCID);
		}
		return nftID;
	}

	// a viewer can view a creator post if the creator account is not private, or it is private and the viewer is a follower
	function notPrivateOrIsFollower(uint id, address viewer) public view returns (bool) {
		address creator = storageContract.getCreator(id);
		return !userContract.isPrivateAccount(creator) || userContract.isFollower(creator, viewer);
	}

	function isValidPost(uint256 id) public view exists(id) returns (bool) {
		return !storageContract.isDeleted(id) && !storageContract.isFlagged(id);
	}	

	// increments the view count for this post. 
	// we do not count duplicate views within a day (i.e even if a user views a post multiple times in 1 day, we count it as he only viewed it at most one time)
	// this reduces the chances of manipulation of viewcounts to gain ad revenue.
	// there are two view counts to maintain
	// 1. overall view count
	// 2. viewcount for this month, to calculate the ad revenue distribution for this monthly period
	function incrViewCount(uint256 id, address viewer) private {
		// prevent duplicate counting of viewcount
		if (block.timestamp - storageContract.lastViewed(id, viewer) < VIEWCOUNT_COOLDOWN) {
			// if the time between now and last viewed is less than 1 day, we do not double count.
			return;
		}

		// post view count
		storageContract.incrementPostViewCount(id);

		// viewcount for this month
		storageContract.incrementMonthlyViewCount(id);
		storageContract.incrementMonthlyTotalViewCount();		
		storageContract.updateLastViewed(id, viewer, block.timestamp);
	}		

	// like the post specified by `id`. the liker is the `msg.sender`
	function like(uint256 id) public canAccess(id, msg.sender) validUser(msg.sender) {
		address liker = msg.sender;
		require(!storageContract.hasLiked(id, liker), "you have already liked this post");
		storageContract.like(id, liker);
		emit PostLiked(liker, id);
	}	

	// unlike the post specified by `id`. the liker is the `msg.sender`
	function unlike(uint256 id) public canAccess(id, msg.sender) {
		address unliker = msg.sender;
		require(storageContract.hasLiked(id, unliker), "you have not liked this post");
		storageContract.unlike(id, unliker);
		emit PostUnliked(unliker, id);
	}

	// add a comment with `text` to post with id of `id`. the commentor is `msg.sender`.
	// returns the id of the comment
	function addComment(uint256 id, string memory text) public canAccess(id, msg.sender) validUser(msg.sender) returns (uint) {
		address commentor = msg.sender;
		uint commentId = storageContract.addComment(id, commentor, text);
		emit Commented(commentor, id, commentId, text);
		return commentId;
	}	

	// delete a comment with the specified postID and commentID.
	// the commentator is `msg.sender`. Only the owner of this comment can delete the comment.
	function deleteComment(uint256 postID, uint256 commentID) public canAccess(postID, msg.sender) {	
		require(storageContract.commentExists(postID, commentID), "invalid comment ID");
		address commentor = msg.sender;
		storageContract.deleteComment(postID, commentID);
		emit CommentDeleted(commentor, postID, commentID, block.timestamp);		
	}

	// delete the post specified by `id`. Only the owner of the post can delete the post.
	function deletePost(uint256 id) public creatorOnly(id) exists(id) notDeleted(id) {
		storageContract.deletePost(id);
		emit PostDeleted(msg.sender, id, block.timestamp);
	}	

	// report this post specified by `id`
	function reportPost(uint256 id) public canAccess(id, msg.sender) validUser(msg.sender) {
		address reporter = msg.sender;
		require(!storageContract.hasReported(id, reporter),"you have already reported this post");

		uint reportCount = storageContract.report(id, reporter);

		if (reportCount >= MAX_REPORT_COUNT) {
			storageContract.setFlagged(id, true);
		}
	}	

	// get the tokenURI (i.e image link) to the NFT specified by `id`
	function getTokenURIByTokenID(uint id) public view returns (string memory) {
		return nftContract.tokenURI(id);
	}

	// get the tokenURI (i.e image link) to the NFT in the post specified by `id`
	function getTokenURIByPostID(uint id) public view canAccess(id, msg.sender) returns (string memory) {
		uint tokenId = storageContract.getNFTID(id);
		require(tokenId > 0, "this post does not have media");
		return getTokenURIByTokenID(tokenId);
	}	

	modifier userContractOnly() {
		require(msg.sender == address(userContract), "user contract only");
		_;
	}

	function setUserContract(User _userContract) public contractOwnerOnly {
		userContract = _userContract;
	}	

	function batchSetDeleted(uint[] memory postIds) external userContractOnly {
		storageContract.batchSetDeleted(postIds);
	}	

	function isCreatorOf(uint256 id, address creator) public view returns (bool) {
		return storageContract.getCreator(id) == creator;
	}

	function getCreator(uint id) public view returns (address) {
		return storageContract.getCreator(id);
	}

	function isFlagged(uint256 id) public view returns (bool) {
		return storageContract.isFlagged(id);
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
	function createAd(address creator, string memory caption, string memory ipfsCID, uint endTime) external AdContractOnly returns (uint) {
		uint nftId = mintNFT(creator, ipfsCID);

		uint id = storageContract.createPost(creator, caption, nftId);
		storageContract.createAdWithPostId(id, endTime);
		
		return id;
	}	

	// choose an advertisement uniformly at random so that each ad gets an equal chance 
	// returns a tuple (ad, found), where ad is the advertisement to return, and found is a bool indicating if we successfully found an ad
	function getAdPost() public returns (PostStorage.Post memory, bool) {
		PostStorage.Post memory adPost;
		bool found = false;
		while (true) {
			uint n = storageContract.getAdsCount();	
			if (n == 0) {
				break;
			}
			
			uint randIdx = rngContract.random() % n;
			// check if this ad is expired or is somehow flagged/deleted
			PostStorage.Ad memory ad = storageContract.getAdvertisementByIndex(randIdx);
			if (ad.endTime < block.timestamp || !isValidPost(ad.postId)) {
				storageContract.removeAdByIdx(randIdx);
			} else {
				adPost = storageContract.getPost(ad.postId);
				found = true;
				break;
			}
		}

		return (adPost, found);
	}	

	function getAdRevenueDistribution() external view AdContractOnly returns (address[] memory, uint[] memory, uint) {
		return (storageContract.getMonthlyViewStatistics());
	}	

	// resets the monthly tracker for view counts
	function resetMonthlyViewCounts() external AdContractOnly {
		storageContract.resetMonthlyViewStatistics();
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

	function resetFlagAndReportCount(uint id) external ContentModerationContractOnly {
		storageContract.resetReportCount(id);
		storageContract.setFlagged(id, false);
	}

	// users can call this function to get a flagged post which has a dispute open.
	// they can only view the post corresponding to the dispute they are voting for.
	function getPostToReviewDispute(uint postId) public view exists(postId) notDeleted(postId) returns (PostStorage.Post memory) {
		address voter = msg.sender;
		require(contentModerationContract.isVotingFor(voter, postId), "you are not voting for the specified post");
		return storageContract.getPost(postId);
	}
	// === END OF CONTENT MODERATION OPERATIONS === 

	function setFeedContract(Feed _feedContract) public contractOwnerOnly {
		feedContract = _feedContract;
	}	

	modifier feedContractOnly() {
		require(address(feedContract) == msg.sender, "feed contract only");
		_;
	}

	function feedIncrViewCount(uint id, address viewer) external feedContractOnly {
		incrViewCount(id, viewer);
	}
}