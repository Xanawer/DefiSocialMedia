pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract Token is ERC20 {
	// owner of this token contract
	address owner; 
	// buy back at 1 token for 0.0009 eth from users
	uint256 BUYBACK_PRICE = 0.0009 ether; 
	// sell users 1 token for 0.001 eth
	uint256 SELL_PRICE = 0.001 ether; 

	constructor() ERC20("DSM Token", "DSMToken") {
		owner = msg.sender;
	}

	function getTokens() public payable {
		uint amt = msg.value / SELL_PRICE;
		_mint(msg.sender, amt);
	}

	function sellTokens(uint amt) public {
		require(amt >= balanceOf(msg.sender), "you have less than the specified amount of tokens to sell");
        uint toReturn = amt * BUYBACK_PRICE;
		_burn(msg.sender, amt);
        payable(msg.sender).transfer(toReturn);
	}
}