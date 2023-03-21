pragma solidity ^0.8.0;

import "./Post.sol";

contract User {
    // Struct to store user data
    struct UserData {
        string name;
        string email;
        uint age;
    }
    
    Post postContract;
    // Mapping to store user data by address
    mapping(address => UserData) private users;

    constructor(Post _postContract) {
        postContract = _postContract;
    }
    
    // Function to create a new user
    function createUser(string memory _name, string memory _email, uint _age) public {
        UserData memory newUser = UserData(_name, _email, _age);
        users[msg.sender] = newUser;
    }
    
    // Function to retrieve user data by address
    function getUser() public view returns(string memory, string memory, uint) {
        UserData memory currentUser = users[msg.sender];
        return (currentUser.name, currentUser.email, currentUser.age);
    }
    
    // Function to update user data
    function updateUser(string memory _name, string memory _email, uint _age) public {
        UserData memory currentUser = users[msg.sender];
        currentUser.name = _name;
        currentUser.email = _email;
        currentUser.age = _age;
        users[msg.sender] = currentUser;
    }
    
    // Function to delete user data
    function deleteUser() public {
        postContract.deleteAllUserPosts(msg.sender);
        delete users[msg.sender];
    }

}