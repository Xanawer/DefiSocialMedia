const truffleAssert = require('truffle-assertions')
const assert = require('assert')

const Post = artifacts.require('Post')
const User = artifacts.require('User')
const Feed = artifacts.require('Feed')

contract('Feed contract', function (accounts) {
  let userContract
  let postContract
  let feedContract

  const creator = accounts[1]
  const viewer = accounts[2]
  const numPosts = 25
  before(async () => {
    userContract = await User.deployed()
    postContract = await Post.deployed()
    feedContract = await Feed.deployed()
    await userContract.createUser('test user 1', 24, { from: creator })
    // add 25 posts to global feed
    for (let i = 0; i < numPosts; i++) {
      await postContract.createPost('zzzzz', `fakeIPFSCID${i}`, {
        from: creator,
      })
    }
  })

  it('can initialize scroll', async () => {
    // first 10
    const posts = await feedContract.startScroll.call() // fake call to return results
    const tx = await feedContract.startScroll() // actual call (changes contract state)
    assert(posts.length == 10)
    for (let i = 0; i < posts.length; i++) {
      assert(posts[i].id == numPosts - i)
    }
  })

  it('can continue scroll', async () => {
    // next 10
    let expectedNextPost = numPosts - 10
    let posts = await feedContract.continueScroll.call() // fake call to return results
    await feedContract.continueScroll() // actual call (changes contract state)
    assert(posts.length == 10)
    for (let i = 0; i < posts.length; i++) {
      assert(posts[i].id == expectedNextPost - i)
    }

    // next 5
    expectedNextPost -= 10
    posts = await feedContract.continueScroll.call() // fake call to return results
    await feedContract.continueScroll() // actual call (changes contract state)
    for (let i = 0; i < 5; i++) {
      assert(posts[i].id == expectedNextPost - i)
    }
  })
})
