pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol';
// ERC721: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/ERC721.sol
// ERC721URIStorage: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/extensions/ERC721URIStorage.sol
contract MediaNFT is ERC721URIStorage {
	address owner;
	string BASE_URI = "https://cloudflare-ipfs.com/ipfs/"; // ipfs gateway, there are many other alternatives as well
	mapping(string => bool) usedImagesSet;
	uint nextTokenID;

	modifier ownerOnly {
		require(owner == msg.sender, "owner only");
		_;
	}

	constructor() ERC721("DefiSocialMediaNFT", "DSMNFT") {
		owner = msg.sender;
		nextTokenID = 0;
	}

	 function _baseURI() internal view virtual override returns (string memory) {
        return BASE_URI;
    }

	// returns id of nft minted
	function mint(address to, string memory ipfsCID) ownerOnly external returns (uint) {
		require(!usedImagesSet[ipfsCID], "this image has already been minted to some nft");
		usedImagesSet[ipfsCID] = true;

		uint tokenID = nextTokenID;
		_safeMint(to, tokenID);
		_setTokenURI(tokenID, ipfsCID);
		nextTokenID++;

		return tokenID;
	}
}