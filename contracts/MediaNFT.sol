pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol';
// ERC721: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/ERC721.sol
// ERC721URIStorage: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/extensions/ERC721URIStorage.sol
contract MediaNFT is ERC721URIStorage {
	// owner of this nft contract
	address owner; 
	// ipfs gateway, there are many other alternatives as well
	string baseURI = "https://cloudflare-ipfs.com/ipfs/"; 
	// keep track of used images, so that we do not accidentally mint the same image to different nfts
	mapping(string => bool) usedImagesSet;
	// running number of token ids
	uint nextTokenID;

	modifier ownerOnly {
		require(owner == msg.sender, "owner only");
		_;
	}

	constructor() ERC721("DefiSocialMediaNFT", "DSMNFT") {
		owner = msg.sender;
		nextTokenID = 0;
	}


	// returns id of nft minted
	// `to` is the address to mint the nft to
	// `ipfsCID` is the identifier in the IPFS network that points to the associated media (can get this through https://nft.storage website or api)
	function mint(address to, string memory ipfsCID) ownerOnly external returns (uint) {
		require(!usedImagesSet[ipfsCID], "this image has already been minted to some nft");
		usedImagesSet[ipfsCID] = true;

		uint tokenID = nextTokenID;
		_safeMint(to, tokenID);
		_setTokenURI(tokenID, ipfsCID);
		nextTokenID++;

		return tokenID;
	}

	function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

	function setBaseURI(string memory __baseURI) public ownerOnly {
		baseURI = __baseURI;
	}
}