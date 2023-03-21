pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract Token is ERC20 {
	// owner of this token contract
	address owner; 
	// buy back at 1 token for 99 gwei from users
	uint256 BUYBACK_PRICE = 99 gwei; 
	// sell users 1 token for 100 gwei
	uint256 SELL_PRICE = 100 gwei; 

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

	modifier ownerOnly() {
		require(msg.sender == owner, "owner only");
		_;
	}

	function withdrawAllEth() public ownerOnly {
		require(address(this).balance > 2300 gwei, "eth withdrawal cannot cover gas cost");
		payable(owner).transfer(address(this).balance);
	}
}