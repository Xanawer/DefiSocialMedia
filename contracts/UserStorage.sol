pragma solidity ^0.8.0;

import "./Authorizable.sol";

contract UserStorage is Authorizable {
    struct Profile {
        address addr;
        string name;
        string email;
        uint age;
        bool deleted;
        bool isPrivateAccount;
        uint followCount;
        uint[] posts;
    }

	// additional info
	struct UserInfo {
		mapping(address => bool) isFollowing;
		address[] followRequests;
		mapping(address => uint) followRequestsIdxMap;
	}

    // Mapping to store user data by address
    mapping(address => Profile) private users;
	mapping(address => UserInfo) userInfos;

	function init(address userLogic) public ownerOnly {
		authorizeContract(userLogic);
	}

	function createUser(address creator, string memory _name, string memory _email, uint _age) external isAuthorized {
		Profile storage user = users[creator];
		user.name = _name;
		user.email = _email;
		user.age = _age;
		user.deleted = false;
		user.isPrivateAccount = false;
		user.followCount = 0;
		delete user.posts;
	}		

	function isDeleted(address user) external view isAuthorized returns (bool) {
		return users[user].deleted;
	}

	function isPrivateAccount(address user) external view isAuthorized returns (bool) {
		return users[user].isPrivateAccount;
	}
	
	function userExists(address user) external view isAuthorized returns (bool) {
		return users[user].addr != address(0);
	}	

	function newPost(address creator, uint postId) external isAuthorized {
		users[creator].posts.push(postId);
	}	


	function getProfile(address user) external view isAuthorized returns (Profile memory) {
		return users[user];
	}		

	function getName(address user) external view isAuthorized returns (string memory) {
		return users[user].name;
	}			

	function getFollowCount(address user) external view isAuthorized returns (uint) {
		return users[user].followCount;
	}	

	function getFollowRequests(address user) external view isAuthorized returns (address[] memory) {
		return userInfos[user].followRequests;
	}		

	function getAllPostIdsByUser(address creator) external view returns (uint[] memory) {
		return users[creator].posts;
	}

	function isFollowing(address user, address follower) external view isAuthorized returns (bool) {
		return userInfos[user].isFollowing[follower];
	}		

	function hasFollowRequest(address user, address requester) external view isAuthorized returns (bool) {
		UserInfo storage userInfo = userInfos[user];
		address[] storage followRequests = userInfo.followRequests;
		uint idx = userInfo.followRequestsIdxMap[requester];

		// check if index is valid. if it is not, means there is no such requester
		return idx < followRequests.length && followRequests[idx] == requester;
	}			

	function removeFromFollowRequests(address user, address requester) external isAuthorized {
		UserInfo storage userInfo = userInfos[user];
		address[] storage followRequests = userInfo.followRequests;
		uint idx = userInfo.followRequestsIdxMap[requester];
		address lastRequest = followRequests[followRequests.length - 1];

		// we want to delete request at index `idx`
		// overwrite element at `idx` with last request, then pop the last element
		followRequests[idx] = lastRequest;
		followRequests.pop();

		// update new idx of last request
		userInfo.followRequestsIdxMap[lastRequest] = idx;
	}			

	function addToFollowRequests(address user, address requester) external isAuthorized {
		UserInfo storage userInfo = userInfos[user];
		address[] storage followRequests = userInfo.followRequests;
		uint idx = followRequests.length;

		followRequests.push(requester);

		userInfo.followRequestsIdxMap[requester] = idx;
	}

	function addFollower(address user, address follower) external isAuthorized {
		UserInfo storage userInfo = userInfos[user];
		userInfo.isFollowing[follower] = true; 
	}		

	function removeFollower(address user, address follower) external isAuthorized {
		UserInfo storage userInfo = userInfos[user];
		userInfo.isFollowing[follower] = false; 
	}		

	function incrFollowCount(address user) external isAuthorized {
		users[user].followCount++;
	}			

	function decrFollowCount(address user) external isAuthorized {
		users[user].followCount--;
	}		

	function setName(address user, string memory name) external isAuthorized  {
		users[user].name = name;
	}		

	function setEmail(address user, string memory email) external isAuthorized  {
		users[user].email = email;
	}		

	function setAge(address user, uint age) external isAuthorized  {
		users[user].age = age;
	}		

	function setPrivate(address user, bool p) external isAuthorized  {
		users[user].isPrivateAccount = p;
	}	

	function setDeleted(address user, bool deleted) external isAuthorized  {
		users[user].deleted = deleted;
	}	
}