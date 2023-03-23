pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import "./Authorizable.sol";

// this token contract serve three purposes
// 1. users can buy/sell tokens from this contract
// 2. store the ads revenue balance
// 3. store the content moderation token balance
contract Token is ERC20 {
	address owner;
	// sell users 1 token for 1000 gwei (~0.002 USD)
	uint256 SELL_PRICE = 1000 gwei; 
	// buy back at 1 token for 90% of sell price
	uint256 BUYBACK_PRICE = SELL_PRICE * 9/10;
	// emergency stop
	bool contractStopped = false;

	modifier emergencyStop() {
		require(!contractStopped, "contract stopped for emergency");
		_;
	}

	constructor() ERC20("DSM Token", "DSMToken") {
		owner = msg.sender;
	}

	modifier ownerOnly {
		require(msg.sender == owner, "owner only");
		_;
	}

	function getTokens() public payable emergencyStop {
		uint amt = msg.value / SELL_PRICE;
		_mint(msg.sender, amt);
	}

	function sellTokens(uint amt) public emergencyStop {
		require(amt >= balanceOf(msg.sender), "you have less than the specified amount of tokens to sell");
        uint toReturn = amt * BUYBACK_PRICE;
		_burn(msg.sender, amt);
        payable(msg.sender).transfer(toReturn);
	}

	function withdrawAllEth() public ownerOnly emergencyStop {
		require(address(this).balance > 2300 gwei, "eth withdrawal cannot cover gas cost");
		payable(owner).transfer(address(this).balance);
	}

	function setContractStopped(bool stop) public ownerOnly {
		contractStopped = stop;
	}

	// stop any transfer if emergency stop is activated
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override emergencyStop {}	
}