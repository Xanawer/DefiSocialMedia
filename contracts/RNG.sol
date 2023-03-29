pragma solidity ^0.8.0;

// a fake random number generator
// note that this is NOT secure. it is only for demonstration and test purposes.
// to get secure random number generators, consider using chainlink's vrf
contract RNG {
	uint fakeRandomNumber;
	
	// returns a random uint
	function random() public view returns (uint) {
		return fakeRandomNumber;
	}

	function setRandom(uint randomNumber) public {
		fakeRandomNumber = randomNumber;
	}
}