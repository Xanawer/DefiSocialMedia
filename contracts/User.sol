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

    modifier userOwnerOnly() {
        require(msg.sender == users[msg.sender].addr, "user owner only");
        _;
    }

    modifier userExists(address addr) {
        require(addr == users[addr].addr, "user does not exist");
        _;
    }

    function exists(address addr) public view returns (bool) {
        return addr == users[addr].addr && !users[addr].deleted;
    }
    
    // Function to create a new user
    function createUser(string memory _name, string memory _email, uint _age) public {
        require(bytes(_name).length > 0, "name is empty");
        require(bytes(_email).length > 0, "email is empty");
        require(_age >= 13, "you are too young");
        UserData memory newUser = UserData(msg.sender, _name, _email, _age, false);
        users[msg.sender] = newUser;
    }
    
    // Function to retrieve user profile
    function getProfile() public view notDeleted(msg.sender) userExists(msg.sender) returns(UserData memory) {
        return users[msg.sender];
    }

    function getName(address user) public view notDeleted(user) userExists(msg.sender) returns(string memory) {
        return users[user].name;
    }

    function updateName(string memory _name) public notDeleted(msg.sender) userOwnerOnly userExists(msg.sender) {
        users[msg.sender].name = _name;
    }

    function updateEmail(string memory _email) public notDeleted(msg.sender) userOwnerOnly userExists(msg.sender) {
        users[msg.sender].email = _email;
    }

    function updateAge(uint _age) public notDeleted(msg.sender) userOwnerOnly userExists(msg.sender) {
        users[msg.sender].age = _age;
    }
    
    // Function to delete user data
    function deleteUser() public notDeleted(msg.sender) userOwnerOnly userExists(msg.sender) {
        postContract.deleteAllUserPosts(msg.sender);
        users[msg.sender].deleted = true;
    }
}