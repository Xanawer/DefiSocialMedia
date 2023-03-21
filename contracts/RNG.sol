pragma solidity ^0.8.0;

// a pseudo random number generator
// note that this is NOT secure. it is only for demonstration purposes.
// to get secure random number generators, consider using chainlink's vrf
contract RNG {
	// history of the randomly generated numbers. this is purely for demonstration & testing purposes.
	uint[] public history;
	// prevents same random value in the same block
	uint counter; 
	
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

	function getLatestHistory() public view returns (uint) {
		return history[history.length -1];
	}

	function getHistoryAt(uint idx) public view returns (uint) {
		require(idx < history.length, "index out of bound");
		return history[idx];
	}
}