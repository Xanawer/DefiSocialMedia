const truffleAssert = require('truffle-assertions')
const assert = require('assert')
const BN = require('bn.js')

const Post = artifacts.require('Post')
const User = artifacts.require('User')
const NFT = artifacts.require('NFT')

contract('Post contract', function (accounts) {
  let userContract
  let postContract
  let nftContract

  const creator = accounts[1]
  const viewer = accounts[2]
  const fakeIPFSCID = 'fake'
  before(async () => {
    userContract = await User.deployed()
    postContract = await Post.deployed()
    nftContract = await NFT.deployed()
    await userContract.createUser('test user 1', 24, { from: creator })
    await userContract.createUser('test user 2', 24, { from: viewer })
  })

  it('can create post', async () => {
    const tx = await postContract.createPost('caption', fakeIPFSCID, {
      from: creator,
    })
    const postId = (await postContract.lastPostId()).toNumber()
    truffleAssert.eventEmitted(
      tx,
      'PostCreated',
      (e) => e.creator == creator && e.postId == postId
    )

    // test token uri of nft
    const expectedTokenURI = (await nftContract.getBaseURI()) + fakeIPFSCID
    const actualTokenURI = await postContract.getTokenURIByPostID(postId)
    assert.strictEqual(expectedTokenURI, actualTokenURI)
  })

  it('can view post', async () => {
    const id = 1
    assert.strictEqual((await postContract.getViewCount(id)).toNumber(), 0)

    await postContract.viewPost(id, { from: viewer })
    assert.strictEqual((await postContract.getViewCount(id)).toNumber(), 1)

    // no double counting within 24hrs
    await postContract.viewPost(id, { from: viewer })
    assert.strictEqual((await postContract.getViewCount(id)).toNumber(), 1)

    // fast forward 1 day
    const one_day = 60 * 60 * 24
    web3.currentProvider.send(
      { jsonrpc: '2.0', method: 'evm_increaseTime', params: [one_day], id: 0 },
      (err1) => {
        if (err1) {
          return reject(err1)
        }
      }
    )

    // after 1 day, allow counting view from viewer again
    await postContract.viewPost(id, { from: viewer })
    assert.strictEqual((await postContract.getViewCount(id)).toNumber(), 2)
  })

  it('can view all post by creator', async () => {
    for (let i = 0; i < 10; i++) {
      await postContract.createPost('lololol', `fakeIPFSCID${i}`, { from: creator })
    }
    const posts = await postContract.viewAllPostsByCreator.call(creator, {
      from: viewer,
    })
    assert.strictEqual(posts.length, 11)
  })

  it('can like and unlike', async () => {
    const postId = 1
    await postContract.like(postId, { from: viewer })
    let post = await postContract.viewPost.call(postId)
    assert(post.likes == 1)

    await postContract.unlike(postId, { from: viewer })
    post = await postContract.viewPost.call(postId)
    assert(post.likes == 0)
  })

  it('can comment and uncomment', async () => {
    const postId = 1
    const text = 'haha so funny'
    await postContract.addComment(postId, text, { from: viewer })
    let post = await postContract.viewPost.call(postId)
    assert(post.comments[0].text == text)

	const commentId = 0
    await postContract.deleteComment(postId, commentId, { from: viewer })
    post = await postContract.viewPost.call(postId)
    assert(post.comments.length == 0)
  })

  it('can delete post', async () => {
    const postId = 1
    await postContract.deletePost(postId, { from: creator })
    await truffleAssert.reverts(postContract.viewPost(postId))
  })
})
