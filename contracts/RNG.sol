pragma solidity ^0.8.0;

// a pseudo random number generator
// note that this is NOT secure. it is only for demonstration purposes.
// to get secure random number generators, consider using chainlink's vrf
contract RNG {
	uint[] public history;
	uint counter; // prevents same random value in the same block
	
	// returns a random uint
	function random() public returns (uint) {
		uint r = uint(keccak256(abi.encodePacked(counter, block.difficulty, block.timestamp)));
		counter++;
		history.push(r);
		return r;
	}

	function historyLength() public view returns (uint) {
		return history.length;
	}
}