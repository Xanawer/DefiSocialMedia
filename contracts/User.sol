pragma solidity ^0.8.0;

import "./Post.sol";

contract User {
    // Struct to store user data
    struct UserData {
        address addr;
        string name;
        string email;
        uint age;
        bool deleted;
        bool isPrivateAccount;
        uint followCount;
    }
    
    Post postContract;
    // Mapping to store user data by address
    mapping(address => UserData) private users;
    // mapping of creator => follower => bool (true if follower is following creator)
    mapping(address => mapping(address => bool)) isFollowing;
    // mapping of creator => requester => index of the requester in `followRequests[creator]` array
    mapping(address => mapping(address => uint)) followRequestsIdxMap;
    // mapping of creator => follow requests
    // this is to easily iterate through follow requests for the case where the creator unprivates his/her account, and the follow requests are automatically accepted
    mapping(address => address[]) followRequests;

    constructor(Post _postContract) {
        postContract = _postContract;
    }

    modifier notDeleted(address user) {
        require(!users[user].deleted, "user has been deleted");
        _;
    }

    modifier userExists(address addr) {
        require(addr == users[addr].addr, "user does not exist");
        _;
    }

    function existsAndNotDeleted(address addr) public view returns (bool) {
        return addr == users[addr].addr && !users[addr].deleted;
    }

    // Function to create a new user
    function createUser(string memory _name, string memory _email, uint _age) public {
        require(bytes(_name).length > 0, "name is empty");
        require(bytes(_email).length > 0, "email is empty");
        require(_age >= 13, "you are too young");
        require(users[msg.sender].addr == address(0), "user already exists");
        UserData storage user = users[msg.sender];
        user.addr = msg.sender;
        user.name = _name;
        user.email = _email;
        user.age = _age;
    }
    
    // Function to retrieve user profile
    function getProfile() public view notDeleted(msg.sender) userExists(msg.sender) returns(UserData memory) {
        return users[msg.sender];
    }

    function getName(address user) public view notDeleted(user) userExists(user) returns(string memory) {
        return users[user].name;
    }

    function getFollowerCount(address user) public view notDeleted(user) userExists(user) returns(uint) {
        return users[msg.sender].followCount;
    }

    function updateName(string memory _name) public notDeleted(msg.sender) userExists(msg.sender) {
        users[msg.sender].name = _name;
    }

    function updateEmail(string memory _email) public notDeleted(msg.sender) userExists(msg.sender) {
        users[msg.sender].email = _email;
    }

    function updateAge(uint _age) public notDeleted(msg.sender) userExists(msg.sender) {
        users[msg.sender].age = _age;
    }

    function privateAccount() public notDeleted(msg.sender) userExists(msg.sender) {
        users[msg.sender].isPrivateAccount = true;
    }

    function unprivateAccount() public notDeleted(msg.sender) userExists(msg.sender) {
        users[msg.sender].isPrivateAccount = false;
        // upon unprivating an account, all follow requests will automatically be accepted
        address[] storage requests = followRequests[msg.sender];
        for (uint i = 0; i < requests.length; i++) {
            address requester = requests[i];
            delete followRequestsIdxMap[msg.sender][requester];
            isFollowing[msg.sender][requester] = true;
        }
        delete followRequests[msg.sender];
    }

    function acceptFollower(address requester) public notDeleted(msg.sender) userExists(msg.sender) { 
        require(hasFollowRequest(msg.sender, requester), "follow request not found");
        // remove requester
        removeRequester(msg.sender, requester);
        // add to following
        isFollowing[msg.sender][requester] = true;
        users[msg.sender].followCount++;
    }

    function removeFollower(address follower) public notDeleted(msg.sender) userExists(msg.sender) {
        require(isFollowing[msg.sender][follower], "follower not found");
        isFollowing[msg.sender][follower] = false;
        users[msg.sender].followCount--;
    }

    function requestFollow(address user) public notDeleted(user) userExists(user) notDeleted(msg.sender) userExists(msg.sender) {
        require(!isFollowing[user][msg.sender], "you have already followed this person");
        require(!hasFollowRequest(user, msg.sender), "you have already requested to follow this person");
        if (isPrivateAccount(user)) {
            // add to follow requests
            followRequestsIdxMap[user][msg.sender] = followRequests[user].length;
            followRequests[user].push(msg.sender);
        } else {
            // if the user is not private, other people can follow him without requesting   
            isFollowing[user][msg.sender] = true;
        }
    }

    function isFollower(address account, address follower) public view notDeleted(account) userExists(account) notDeleted(follower) userExists(follower) returns (bool) {
        return isFollowing[account][follower];
    }

    function hasFollowRequest(address account, address requester) private view notDeleted(account) userExists(account) notDeleted(requester) userExists(requester) returns (bool) {
        uint idx = followRequestsIdxMap[account][requester];
        address[] storage requests = followRequests[account];
        bool foundRequester = idx < requests.length && requests[idx] == requester;
        return foundRequester;
    }

    function removeRequester(address account, address requester) private notDeleted(account) userExists(account) notDeleted(requester) userExists(requester) {
        uint idx = followRequestsIdxMap[account][requester];
        address[] storage requests = followRequests[account];
        requests[idx] = requests[requests.length - 1];
        requests.pop();
        delete followRequestsIdxMap[msg.sender][requester];
    }

    function isPrivateAccount(address addr) public view notDeleted(addr) userExists(addr) returns (bool) {
        return users[addr].isPrivateAccount;
    }

    // Function to delete user data
    function deleteUser() public notDeleted(msg.sender) userExists(msg.sender) {
        postContract.deleteAllUserPosts(msg.sender);
        users[msg.sender].deleted = true;
    }

}