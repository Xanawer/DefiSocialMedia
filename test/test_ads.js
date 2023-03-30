const truffleAssert = require('truffle-assertions')
const assert = require('assert')
const BN = require('bn.js')

const Post = artifacts.require('Post')
const User = artifacts.require('User')
const Feed = artifacts.require('Feed')
const Ads = artifacts.require('AdsMarket')
const Token = artifacts.require('Token')

contract('Ads contract', function (accounts) {
  let userContract
  let postContract
  let feedContract
  let adsContract
  let tokenContract

  const creator1 = accounts[1]
  const creator2 = accounts[2]
  const advertiser = accounts[3]
  const numPosts = 26
  const oneEth = new BN('10').pow(new BN(18)) // 1 eth
  const tokenPrice = new BN(1000000000000) // 1000 gwei

  before(async () => {
    userContract = await User.deployed()
    postContract = await Post.deployed()
    feedContract = await Feed.deployed()
    adsContract = await Ads.deployed()
    tokenContract = await Token.deployed()

    await userContract.createUser('test user 1', 24, { from: creator1 })
    await userContract.createUser('test user 2', 24, { from: creator2 })
    await userContract.createUser('advertiser', 25, { from: advertiser })

    // add 26 posts to global feed
    // equal number of pots betweenc creator 1 and 2
    for (let i = 0; i < numPosts; i++) {
      const creator = i % 2 === 0 ? creator1 : creator2
      await postContract.createPost('zzzzz', `fakeIPFSCID${i}`, {
        from: creator,
      })
    }
  })

  it('can create ad', async () => {
    // buy tokens
    await tokenContract.buyTokens({ from: advertiser, value: oneEth })
    // approve ads contract to transfer tokens
    await tokenContract.approve(Ads.address, 1000000000, { from: advertiser })
    const expectedTokens = oneEth / tokenPrice
    const actualTokens = (await tokenContract.balanceOf(advertiser)).toNumber()
    assert(expectedTokens == actualTokens)

    // create ad for 1 day
    await truffleAssert.passes(
      adsContract.createAd('ad', 'fakeadipfscid', 1, { from: advertiser })
    )
  })

  it('get ad', async () => {
    const ad = await postContract.getAdPost.call()
    const found = ad[1]
    const adPost = ad[0]
    assert.ok(found)
    assert(adPost.creator == advertiser)
  })

  it('test ads injection', async () => {
    const advertId = numPosts + 1

    const posts = await feedContract.startScroll.call()
    assert(posts[5].id == advertId) // injected at index 5
  })

  it('test payout', async () => {
    const adsRevenue = 1000 * 0.9 // after minus commission
    // mock viewcounts, each post should have equal number of views, so the 2 creators should get equal payout
    for (let i = 0; i < 3; i++) {
      await feedContract.startScroll({ from: accounts[i] })
      await feedContract.continueScroll({ from: accounts[i] })
      await feedContract.continueScroll({ from: accounts[i] })
    }

    await adsContract.payout()

    const afterBalance1 = (
      await adsContract.getPayoutBalance({ from: creator1 })
    ).toNumber()
    const afterBalance2 = (
      await adsContract.getPayoutBalance({ from: creator2 })
    ).toNumber()

    // both should have split the ads revenue equally
    assert(afterBalance2 == adsRevenue / 2)
    assert(afterBalance1 == afterBalance2)
  })

  it('cannot payout again within 30 days period', async () => {
    await truffleAssert.reverts(adsContract.payout())
  })

  it('can withdraw payout', async () => {
    const payout = 450
    await adsContract.withdraw(payout, { from: creator1 })
    const tokenBalance = (await tokenContract.balanceOf(creator1)).toNumber()
    assert(tokenBalance == 450)

    const creator1BalanceInAdsContract = (
      await adsContract.getPayoutBalance({ from: creator1 })
    ).toNumber()
    assert(creator1BalanceInAdsContract == 0)
  })
})
