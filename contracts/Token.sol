pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract Token is ERC20 {
	address owner;
	uint256 BUYBACK_PRICE = 0.0009 ether; // buy back at 1 token for 0.0009 eth
	uint256 SELL_PRICE = 0.001 ether; // sell users 1 token for 0.001 eth

	constructor() ERC20("DSM Token", "DSMToken") {
		owner = msg.sender;
	}

	// in reality, tokens should be traded and get from AMM/DEX.
	// this is just a proof of concept so we use this function to get tokens easily.
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