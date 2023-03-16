pragma solidity ^0.5.0;

contract User {
    
    // Struct to store user data
    struct UserData {
        string name;
        string email;
        uint age;
    }
    
    // Mapping to store user data by address
    mapping(address => UserData) private users;
    
    // Function to create a new user
    function createUser() public {
    }
    
    // Function to retrieve user data by address
    function getUser() public {
    }
    
    // Function to update user data
    function updateUser() public {
    }
    
    // Function to delete user data
    function deleteUser() public {
    }
}