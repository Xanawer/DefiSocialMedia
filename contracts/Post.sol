pragma solidity ^0.8.0;

import "./MediaNFT.sol";

contract Post {
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
	uint256 nextPostID = 0;
	mapping(uint256 => PostData) idToPost;
	// ensures that for each post, there are no duplicate likes for this account (i.e an account cannot like a post twice)
	mapping(uint256 => mapping(address => bool)) hasLiked; 


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

	modifier contractOwnerOnly() {
		require(msg.sender == owner, "only owner of this contract can do this action");
		_;
	}

	constructor () {
		nftContract = new MediaNFT();
		owner = msg.sender;
	}

	function incrViewCount(uint256 id) private {
		idToPost[id].viewCount++;
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

	function createPost(string memory caption, string memory ipfsCID) public {
		// default value of -1 indicates this post does not have any media attached to it
		int mediaNFTID = -1;
		// if this post has a media (i.e cid fill is non empty)
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
}

