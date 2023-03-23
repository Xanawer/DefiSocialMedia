pragma solidity ^0.8.0;

import "./Post.sol";
import "./UserStorage.sol";

contract User{
	Post postContract;
	UserStorage storageContract;

    constructor(Post _postContract, UserStorage _storageContract) {
        postContract = _postContract;
		storageContract = _storageContract;
    }	

	modifier notDeleted(address user) {
        require(!storageContract.isDeleted(user), "user has been deleted");
        _;
    }

    modifier userExists(address addr) {
        require(storageContract.userExists(addr), "user does not exist");
        _;
    }
	
	// m for modifier
    modifier mValidUser(address addr) {
        require(storageContract.userExists(addr) && !storageContract.isDeleted(addr), "not valid user");
        _;
    }

    // valid user defined as a user that exists and is not deleted
    function validUser(address addr) public view returns (bool) {
        return storageContract.userExists(addr) && !storageContract.isDeleted(addr);
    }

	function getAllPostIdsByUser(address creator) public view mValidUser(creator) returns (uint[] memory) {
		return storageContract.getAllPostIdsByUser(creator);
	}

	function newPost(address creator, uint postId) public  mValidUser(creator) {
		require(msg.sender == address(postContract), "post contract only");
		storageContract.newPost(creator, postId);
	}	

    // Function to create a new user
    function createUser(string memory _name, string memory _email, uint _age) public {
		address creator = msg.sender;
        require(bytes(_name).length > 0, "name is empty");
        require(bytes(_email).length > 0, "email is empty");
        require(_age >= 13, "you are too young");
        require(!storageContract.userExists(creator), "user already exists");
        storageContract.createUser(creator, _name, _email, _age);
    }
    
    // Function to retrieve user profile
    function getProfile() public view mValidUser(msg.sender) returns(UserStorage.Profile memory) {
        return storageContract.getProfile(msg.sender);
    }

    function getName(address user) public view mValidUser(user) returns(string memory) {
        return storageContract.getName(user);
    }

    function getFollowerCount(address user) public view mValidUser(user)  returns(uint) {
        return storageContract.getFollowCount(user);
    }

    function updateName(string memory name) public mValidUser(msg.sender)   {
        storageContract.setName(msg.sender, name);
    }
    function updateEmail(string memory email) public mValidUser(msg.sender)   {
        storageContract.setEmail(msg.sender, email);
    }
    function updateAge(uint age) public mValidUser(msg.sender)   {
        storageContract.setAge(msg.sender, age);
    }

    function privateAccount() public mValidUser(msg.sender) {
        storageContract.setPrivate(msg.sender, true);
    }

    function unprivateAccount() public mValidUser(msg.sender) {
		address creator = msg.sender;
        storageContract.setPrivate(msg.sender, false);
		address[] memory requests = storageContract.getFollowRequests(msg.sender);
        for (uint i = 0; i < requests.length; i++) {
			address requester = requests[i];
            storageContract.removeFromFollowRequests(creator, requester);
			storageContract.addFollower(creator, requester);
			storageContract.incrFollowCount(creator);
        }
    }

    function acceptFollower(address requester) public mValidUser(msg.sender) { 
		address creator = msg.sender;
        require(storageContract.hasFollowRequest(creator, requester), "follow request not found");
        // remove requester
		storageContract.removeFromFollowRequests(creator, requester);
        // follow
		storageContract.addFollower(creator, requester);
		storageContract.incrFollowCount(creator);
    }

    function removeFollower(address follower) public mValidUser(msg.sender) {
		address creator = msg.sender;
        require(storageContract.isFollowing(creator, follower), "follower not found");
        storageContract.removeFollower(creator, follower);
		storageContract.decrFollowCount(creator);		
    }

    function requestFollow(address requester) public mValidUser(msg.sender) mValidUser(requester)  {
		address creator = msg.sender;
        require(!storageContract.isFollowing(creator, requester), "you have already followed this person");
        require(!storageContract.hasFollowRequest(creator, requester), "you have already requested to follow this person");

        if (storageContract.isPrivateAccount(creator)) {
            // add to follow requests
            storageContract.addToFollowRequests(creator, requester);
        } else {
            // if the user is not private, other people can follow him without requesting   
            storageContract.addFollower(creator, requester);
			storageContract.incrFollowCount(creator);
        }
    }

    function isFollower(address creator, address follower) public view mValidUser(creator) mValidUser(follower)  returns (bool) {
        return storageContract.isFollowing(creator, follower);
    }

    function isPrivateAccount(address addr) public view mValidUser(addr) returns (bool) {
        return storageContract.isPrivateAccount(addr);
    }

    // Function to delete user data
    function deleteUser() public mValidUser(msg.sender) {
		address creator = msg.sender;
        postContract.batchSetDeleted(storageContract.getAllPostIdsByUser(creator));
        storageContract.setDeleted(creator, true);
    }	
}