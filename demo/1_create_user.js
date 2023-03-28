const AdsMarket = artifacts.require('AdsMarket')
const ContentModeration = artifacts.require('ContentModeration')
const ContentModerationStorage = artifacts.require('ContentModerationStorage')
const NFT = artifacts.require('NFT')
const Post = artifacts.require('Post')
const PostStorage = artifacts.require('PostStorage')
const RNG = artifacts.require('RNG')
const Token = artifacts.require('Token')
const User = artifacts.require('User')
const UserStorage = artifacts.require('UserStorage')
const Feed = artifacts.require('Feed')

// run `truffle migrate` if u havent deployed your contracts on ganache
// run this demo with `truffle exec demo/1_create_user.js`
module.exports = async function (callback) {
	try {
		const userContract = await User.deployed()
		// const accounts = await web3.eth.getAccounts()

		await userContract.createUser('test user1', 13)
		const userProfile = await userContract.getProfile()
		console.log({ userProfile })

	} catch(error) {
		console.error(error)
	} finally {
		callback()
	}
}
