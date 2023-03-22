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
        address[] followers;
        address[] followRequests;
    }
    
    Post postContract;
    // Mapping to store user data by address
    mapping(address => UserData) private users;

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

    function exists(address addr) public view returns (bool) {
        return addr == users[addr].addr && !users[addr].deleted;
    }

    function isPrivateAccount(address addr) public view notDeleted(addr) userExists(addr) returns (bool) {
        return users[addr].isPrivateAccount;
    }

    function isFollower(address account, address follower) public view notDeleted(account) userExists(account) notDeleted(follower) userExists(follower) returns (bool) {
        address[] storage followers = users[account].followers;
        for (uint i = 0; i < followers.length; i++) {
            if (followers[i] == follower) return true;
        }

        return false;
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
        return users[user].followers.length;
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
    }

    function acceptFollower(address requester) public notDeleted(msg.sender) userExists(msg.sender) {
        address[] storage requests = users[msg.sender].followRequests;
        bool found = false;
        for (uint i = 0; i < requests.length; i++) {
            if (requests[i] == requester) {
                found = true;
                // remove the requester from follow request list
                requests[i] = requests[requests.length - 1];
                requests.pop();
                break;
            }
        }
        require(found, "follow request not found");
        users[msg.sender].followers.push(requester);
    }

    function removeFollower(address follower) public notDeleted(msg.sender) userExists(msg.sender) {
        address[] storage followers = users[msg.sender].followers;
        bool found = false;
        for (uint i = 0; i < followers.length; i++) {
            if (followers[i] == follower) {
                found = true;
                // remove the follower from follow request list
                followers[i] = followers[followers.length - 1];
                followers.pop();
                break;
            }
        }
        require(found, "follower not found");
    }

    function requestFollow(address user) public notDeleted(user) userExists(user) notDeleted(msg.sender) userExists(msg.sender) {
        address[] storage followers = users[user].followers;
        address[] storage requesters = users[user].followers;
        for (uint i = 0; i < followers.length; i++) {
            require(followers[i] != msg.sender, "you have already followed this person");
        }
        for (uint i = 0; i < requesters.length; i++) {
            require(requesters[i] != msg.sender, "you have already requested to follow this person");
        }

        requesters.push(msg.sender);
    }
    
    // Function to delete user data
    function deleteUser() public notDeleted(msg.sender) userExists(msg.sender) {
        postContract.deleteAllUserPosts(msg.sender);
        users[msg.sender].deleted = true;
    }

}