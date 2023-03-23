pragma solidity ^0.8.0;

//  contracts that inherit this can authorize other contracts to execute functions with the isAuthorized modifier
abstract contract Authorizable {
	address owner;
	mapping(address => bool) authorizedContracts;	

	constructor() {
		owner = msg.sender;
	}	

	modifier ownerOnly() {
		require(msg.sender == owner, "owner only function");
		_;
	}

	modifier isAuthorized() {
		require(authorizedContracts[msg.sender], "contract not authorized to perform this action");
		_;
	}

	function authorizeContract(address c) internal ownerOnly {
		authorizedContracts[c] = true;
	}

	function unauthorizeContract(address c) internal ownerOnly {
		authorizedContracts[c] = false;
	}
}