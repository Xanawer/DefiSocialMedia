pragma solidity ^0.8.0;
 
import "./Authorizable.sol";

contract PostStorage is Authorizable {
	// === POST DATA STRUCTURES ===
	struct Comment {
		uint256 id;
		address owner;
		uint256 timestamp;
		string text;
	}

	struct Post {
		uint256 id;
		address creator;
		string caption;
		uint nftID; // value of 0 indicates no media
		uint likes;
		uint256 timestamp;
		Comment[] comments;
		uint256 viewCount;
	}

	// to help to keep track  addtional info for each post, 
	struct PostInfo {
		mapping(address => bool) hasLiked; 
		mapping(address => uint256) lastViewed;
		mapping(address => bool) hasReported;
		// mapping of commentId to its index in the `comment array`
		mapping(uint => uint) commentIdxMap;

		uint256 reportCount;
		bool deleted;
		bool flagged;		
	}

	// running number of post ids
	uint256 nextPostId = 1; // id 0 is reserved for detecting if post does not exist
	// mapping of postID to the post structs
	mapping(uint256 => Post) posts;
	mapping(uint => PostInfo) postInfos;

	
	// === ADVERTISEMENT DATA STRUCTURES ===
	// struct for advertisement posts
	struct Ad {
		uint postId;
		uint256 endTime;
	}

	// Info for all posts for this month
	struct MonthlyViewInfo {
		address[] payees;
		uint[] viewCounts;
		uint totalViewCount;
		// track the index where creator is stored in the `payees` array.
		mapping(address => uint) creatorToIdx;
		mapping(uint => uint) viewCountsByPost;
	}
	MonthlyViewInfo monthlyViewInfo;
	// list of all of the current advertisements
	Ad[] ads;	

	function init(address postLogic, address feedContract) public ownerOnly {
		authorizeContract(postLogic);
		authorizeContract(feedContract);
	}

	function createPost(address creator, string memory caption, uint nftID) external isAuthorized returns (uint) {
		Post storage post = posts[nextPostId];
		post.id = nextPostId;
		post.creator = creator;
		post.caption = caption;
		post.nftID = nftID;
		post.likes = 0;
		delete post.comments;
		post.timestamp = block.timestamp;
		post.viewCount = 0;

		nextPostId++;
		return post.id;
	}	

	function incrementMonthlyViewCount(uint id) external isAuthorized {
		monthlyViewInfo.viewCountsByPost[id]++;

		address creator = posts[id].creator;
		address[] storage payees = monthlyViewInfo.payees;
		uint[] storage viewCounts = monthlyViewInfo.viewCounts;		
		// idx of this creator in the `payees` array
		uint idx = monthlyViewInfo.creatorToIdx[creator];
		// check if we are already tracking this creator (i.e the creator at `payeesThisMonth[idx]` is really the creator)		
		bool creatorAlreadyTracked = idx < payees.length && payees[idx] == creator;
		if (!creatorAlreadyTracked) {
			// this creator has not been tracked this month, add it to the end of the array and track the index of where it was stored			
			idx = payees.length;
			monthlyViewInfo.creatorToIdx[creator] = idx;
			payees.push(creator);
			viewCounts.push(0);
		}

		// increment viewcounts for this post for this month 
		viewCounts[idx]++;
	}

	function removeAllMonthlyViewCountByPost(uint id) external isAuthorized {
		uint viewCount = monthlyViewInfo.viewCountsByPost[id];
		if (viewCount == 0) {
			// if this post has no viewcount this month, we dont need to do anything
			return;
		}
		// remove from monthly  total view count
		monthlyViewInfo.totalViewCount -= viewCount;
		
		
		address creator = posts[id].creator;
		// idx of creator in payee and viewcounts array
		uint idx = monthlyViewInfo.creatorToIdx[creator];
		// remove from creator's viewcount
		monthlyViewInfo.viewCounts[idx] -= viewCount;
		if (monthlyViewInfo.viewCounts[idx] == 0) {
			// if monthly view count of this creator becomes 0, remove him from the payee and viewcounts array
			address[] storage payee = monthlyViewInfo.payees;
			uint[] storage viewCounts = monthlyViewInfo.viewCounts;
			// remove from payees array
			address lastPayee = payee[payee.length - 1];
			payee[idx] = lastPayee;
			payee.pop();
			monthlyViewInfo.creatorToIdx[lastPayee] = idx;
			// remove from viewcounts array
			viewCounts[idx] = viewCounts[viewCounts.length - 1];
			viewCounts.pop();
		}

	}

	function like(uint id, address liker) external isAuthorized {
		postInfos[id].hasLiked[liker] = true;
		posts[id].likes++;
	}		

	function unlike(uint id, address unliker) external isAuthorized {
		postInfos[id].hasLiked[unliker] = false;
		posts[id].likes--;
	}			

	function deletePost(uint id) external isAuthorized {
		postInfos[id].deleted = true;
	}	

	function addComment(uint id, address _owner, string memory text) external isAuthorized returns (uint) {
		uint256 commentID = posts[id].comments.length;
		posts[id].comments.push(Comment(commentID, _owner, block.timestamp, text));
		postInfos[id].commentIdxMap[commentID] = commentID;
		return commentID;
	}	

	function commentExists(uint postId, uint commentId) external view isAuthorized returns (bool) {
		uint idx = postInfos[postId].commentIdxMap[commentId];
		Comment[] storage comments = posts[postId].comments;
		return idx < comments.length && comments[idx].id == commentId;
	}

	function deleteComment(uint postId, uint commentId) external isAuthorized {
		uint idx = postInfos[postId].commentIdxMap[commentId];
		Comment[] storage comments = posts[postId].comments;
		// swap this comment with the last, then pop the last element
		// essentially delets the comment at index `idx`
		Comment storage lastComment = comments[comments.length - 1];
		comments[idx] = lastComment;
		comments.pop();

		// save the new index of the last comment
		postInfos[postId].commentIdxMap[lastComment.id] = idx;
	}		

	function hasReported(uint id, address reporter) external view isAuthorized returns (bool) {
		return postInfos[id].hasReported[reporter];
	}

	function report(uint id, address reporter) external isAuthorized returns (uint) {
		postInfos[id].hasReported[reporter] = true;
		postInfos[id].reportCount++;
		return postInfos[id].reportCount;
	}

	function setFlagged(uint id, bool flag) external isAuthorized {
		postInfos[id].flagged = flag;
	}	

	function resetReportCount(uint id) external isAuthorized {
		postInfos[id].reportCount = 0;
	}	
	function getNFTID(uint id) external view isAuthorized returns (uint) {
		return posts[id].nftID;
	}		

	function batchSetDeleted(uint[] memory _posts) external isAuthorized {
		for (uint i = 0; i <_posts.length; i++) {
			postInfos[_posts[i]].deleted = true;
		}
	}	

	function createAdWithPostId(uint id, uint endTime) external isAuthorized {
		Ad storage ad = ads.push();
		ad.postId = id;
		ad.endTime = endTime;
	}

	function getAdsCount() external view isAuthorized returns (uint) {
		return ads.length;
	}	

	function getAdvertisementByIndex(uint idx) external view isAuthorized returns (Ad memory) {
		return ads[idx];
	}	

	function removeAdByIdx(uint idx) external isAuthorized {
		ads[idx] = ads[ads.length - 1];
		ads.pop();
	}			

	function postExists(uint id) external view isAuthorized returns (bool) {
		return posts[id].id != 0;
	}	

	function isDeleted(uint id) external view isAuthorized returns (bool) {
		return postInfos[id].deleted;
	}	

	function isFlagged(uint id) external view isAuthorized returns (bool) {
		return postInfos[id].flagged;
	}	

	function getPost(uint id) external view isAuthorized returns (Post memory) {
		return posts[id];
	}	

	function getCreator(uint id) external view isAuthorized returns (address) {
		return posts[id].creator;
	}	

	function lastViewed(uint id, address viewer) external view isAuthorized returns (uint) {
		return postInfos[id].lastViewed[viewer];
	}

	function incrementPostViewCount(uint id) external isAuthorized  {
		posts[id].viewCount++;
	}		

	function incrementMonthlyTotalViewCount() external isAuthorized {
		monthlyViewInfo.totalViewCount++;
	}

	function getMonthlyViewStatistics() external view isAuthorized returns (address[] memory, uint[] memory, uint) {
		return (monthlyViewInfo.payees, monthlyViewInfo.viewCounts, monthlyViewInfo.totalViewCount);
	}

	function resetMonthlyViewStatistics() external isAuthorized  {
		delete monthlyViewInfo;
	}

	function updateLastViewed(uint id, address viewer, uint _lastViewed) external isAuthorized {
		postInfos[id].lastViewed[viewer] = _lastViewed;
	}	

	function hasLiked(uint id, address liker) external view isAuthorized returns (bool) {
		return postInfos[id].hasLiked[liker];
	}			

	function lastPostId() external view isAuthorized returns (uint) {
		require(nextPostId > 1, "no posts");
		return nextPostId - 1;
	}	

	function getViewCount(uint id) external view isAuthorized returns (uint) {
		return posts[id].viewCount;
	}
}