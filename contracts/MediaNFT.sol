pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC721/ERC721.sol';
// ERC721: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/ERC721.sol

contract MediaNFT is ERC721 {
	string baseURI; // base URI that links to the media of this NFT
	address owner;

	modifier ownerOnly {
		require(owner == msg.sender, "owner only");
		_;
	}
	constructor(string memory __baseURI) ERC721("DefiSocialMediaNFT", "DSM") {
	 	baseURI = __baseURI;
		owner = msg.sender;
	}

	function setBaseURI(string memory __baseURI) ownerOnly public {
		baseURI = __baseURI;
	}

	 function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

	function mint(address to, uint tokenID) ownerOnly external {
		_safeMint(to, tokenID);
	}
}