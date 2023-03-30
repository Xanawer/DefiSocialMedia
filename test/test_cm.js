const truffleAssert = require('truffle-assertions')
const assert = require('assert')
const BN = require('bn.js')

const Post = artifacts.require('Post')
const User = artifacts.require('User')
const Feed = artifacts.require('Feed')
const CM = artifacts.require('ContentModeration')
const Token = artifacts.require('Token')

contract('CM contract', function (accounts) {
  let userContract
  let postContract
  let feedContract
  let cmContract
  let tokenContract

  const creator1 = accounts[1]
  const numPosts = 10
  const oneEth = new BN('10').pow(new BN(18)) // 1 eth
  const tokenPrice = new BN(1000000000000) // 1000 gwei
  const initBalance = oneEth.div(tokenPrice)
  const OPEN_DISPUTE_LOCKED_AMT = new BN(1000)
  const VOTE_LOCKED_AMT = new BN(100)
  const minVote = 8

  const maxReportCount = 4
  const post = 1

  before(async () => {
    userContract = await User.deployed()
    postContract = await Post.deployed()
    feedContract = await Feed.deployed()
    cmContract = await CM.deployed()
    tokenContract = await Token.deployed()

    // buy tokens for everyone, also approve content moderation contract to spend token for everyone
    // also create account for everyone
    for (let i = 0; i < accounts.length; i++) {
      await userContract.createUser('test user', 24, { from: accounts[i] })
      await tokenContract.buyTokens({ from: accounts[i], value: oneEth })
      // approve ads contract to transfer tokens
      await tokenContract.approve(CM.address, 1000000000, { from: accounts[i] })
    }

    // add 10 posts to global feed
    for (let i = 0; i < numPosts; i++) {
      await postContract.createPost('zzzzz', `fakeIPFSCID${i}`, {
        from: creator1,
      })
    }

    await postContract.setMaxReportCount(maxReportCount)
    await cmContract.setMinVoteCount(minVote)
  })

  it('can flag post', async () => {
    for (let i = 0; i < maxReportCount; i++) {
      await postContract.reportPost(post, { from: accounts[i] })
    }

    assert(await postContract.isFlagged(post))

    // check flagged post is not shown in feed
    const posts = await feedContract.startScroll.call()
    const filtered = posts.filter((x) => x.id == 1)
    assert(filtered.length == 0)
  })

  it('can open dispute', async () => {
    const reason = 'wrongly flagged'
    await cmContract.openDispute(post, reason, { from: creator1 })
    assert((await cmContract.getReason(post)) == reason)

    // check balance
    const balance = await tokenContract.balanceOf(creator1)
    assert(balance.eq(initBalance.sub(OPEN_DISPUTE_LOCKED_AMT)))
  })

  it('cannot open 2 dispute for same post', async () => {
    await truffleAssert.reverts(
      cmContract.openDispute(post, 'aosdoasodaod', { from: creator1 })
    )
  })

  it('tie', async () => {
    let approveCount = 0
    for (let i = 0; i < minVote + 1; i++) {
      if (accounts[i] === creator1) {
        // creator should not be able to vote
        await truffleAssert.reverts(
          cmContract.allocateDispute({ from: accounts[i] })
        )
        continue
      }

      // allocate disputes
      await cmContract.allocateDispute({ from: accounts[i] })
      assert(
        (
          await cmContract.getAllocatedDispute({ from: accounts[i] })
        ).toNumber() == post
      )

      // check balance
      const balance = await tokenContract.balanceOf(accounts[i])
      assert(balance.eq(initBalance.sub(VOTE_LOCKED_AMT)))

      // vote
      let approve = approveCount >= 4
      approveCount++
      await cmContract.vote(approve, { from: accounts[i] })
    }

    // cannot end dispute within 1 day
    await truffleAssert.reverts(cmContract.endDispute(post))

    // fast forard 1 day of time
    const one_day = 60 * 60 * 24
    web3.currentProvider.send(
      { jsonrpc: '2.0', method: 'evm_increaseTime', params: [one_day], id: 0 },
      (err1) => {
        if (err1) {
          return reject(err1)
        }
      }
    )

    let tx = await cmContract.endDispute(post)
    truffleAssert.eventEmitted(tx, 'DisputeTied', (e) => e.postId == post)

    // check if everyone get back their balance
    for (let i = 0; i < minVote + 1; i++) {
      // check balance
      const balance = await cmContract.getBalance({ from: accounts[i] })
      let expectedBalance =
        accounts[i] == creator1 ? OPEN_DISPUTE_LOCKED_AMT : VOTE_LOCKED_AMT
      expectedBalance = new BN(expectedBalance)
      assert(balance.eq(expectedBalance))
    }

    // check that post is still flagged
    assert(await postContract.isFlagged(post))
  })

  it('approve', async () => {
    const post = 2
    // flag a new post and open dispute
    for (let i = 0; i < maxReportCount; i++) {
      await postContract.reportPost(post, { from: accounts[i] })
    }

    assert(await postContract.isFlagged(post))
    await cmContract.openDispute(post, 'aosdoasodaod', { from: creator1 })

    for (let i = 0; i < minVote + 1; i++) {
      if (accounts[i] === creator1) {
        // creator should not be able to vote
        await truffleAssert.reverts(
          cmContract.allocateDispute({ from: accounts[i] })
        )
        continue
      }

      // allocate disputes
      await cmContract.allocateDispute({ from: accounts[i] })
      assert(
        (
          await cmContract.getAllocatedDispute({ from: accounts[i] })
        ).toNumber() == post
      )

      // check balance
      const balance = await tokenContract.balanceOf(accounts[i])
      assert(balance.eq(initBalance.sub(VOTE_LOCKED_AMT.mul(new BN(2)))))

      // vote
      let approve = i % 3 != 0
      await cmContract.vote(approve, { from: accounts[i] })
    }

    // cannot end dispute within 1 day
    await truffleAssert.reverts(cmContract.endDispute(post))

    // fast forard 1 day of time
    const one_day = 60 * 60 * 24
    web3.currentProvider.send(
      {
        jsonrpc: '2.0',
        method: 'evm_increaseTime',
        params: [one_day],
        id: 0,
      },
      (err1) => {
        if (err1) {
          return reject(err1)
        }
      }
    )

    const tx = await cmContract.endDispute(post)
    truffleAssert.eventEmitted(tx, 'DisputeApproved', (e) => e.postId == post)

    // check that creator gets back his token, and post is unflagged
    const creatorBalance = await cmContract.getBalance({ from: creator1 })
    assert(creatorBalance.eq(OPEN_DISPUTE_LOCKED_AMT.mul(new BN(2)))) // x2 because he previously got 1 batch unlocked by previous tie
    assert(!(await postContract.isFlagged(post)))

    // check that approvers get rewarded, rejectors get penalized
    for (let i = 0; i < minVote + 1; i++) {
      if (accounts[i] == creator1) continue

      // check balance
      const balance = await cmContract.getBalance({ from: accounts[i] })
      let approve = i % 3 != 0

      if (approve) {
        assert(balance.gt(VOTE_LOCKED_AMT.mul(new BN(2)))) // x2 because he previously got 1 batch unlocked by previous tie
      }
    }
  })

  it('reject', async () => {
    const post = 3
    // flag a new post and open dispute
    for (let i = 0; i < maxReportCount; i++) {
      await postContract.reportPost(post, { from: accounts[i] })
    }

    assert(await postContract.isFlagged(post))
    await cmContract.openDispute(post, 'aosdoasodaod', { from: creator1 })

    for (let i = 0; i < minVote + 1; i++) {
      if (accounts[i] === creator1) {
        // creator should not be able to vote
        await truffleAssert.reverts(
          cmContract.allocateDispute({ from: accounts[i] })
        )
        continue
      }

      // allocate disputes
      await cmContract.allocateDispute({ from: accounts[i] })
      assert(
        (
          await cmContract.getAllocatedDispute({ from: accounts[i] })
        ).toNumber() == post
      )

      // check balance
      const balance = await tokenContract.balanceOf(accounts[i])
      assert(balance.eq(initBalance.sub(VOTE_LOCKED_AMT.mul(new BN(3)))))

      // vote
      let approve = i % 3 == 0
      await cmContract.vote(approve, { from: accounts[i] })
    }

    // cannot end dispute within 1 day
    await truffleAssert.reverts(cmContract.endDispute(post))

    // fast forard 1 day of time
    const one_day = 60 * 60 * 24
    web3.currentProvider.send(
      {
        jsonrpc: '2.0',
        method: 'evm_increaseTime',
        params: [one_day],
        id: 0,
      },
      (err1) => {
        if (err1) {
          return reject(err1)
        }
      }
    )

    const tx = await cmContract.endDispute(post)
    truffleAssert.eventEmitted(tx, 'DisputeRejected', (e) => e.postId == post)

    // check that creator DOES NOT gets back his token, and post REMAINS unflagged
    const creatorBalance = await cmContract.getBalance({ from: creator1 })
    assert(creatorBalance.eq(OPEN_DISPUTE_LOCKED_AMT.mul(new BN(2)))) // x2 because he previously got 1 batch unlocked by previous tie & approve
    assert(await postContract.isFlagged(post))

    // check that approvers get rewarded, rejectors get penalized
    for (let i = 0; i < minVote + 1; i++) {
      if (accounts[i] == creator1) continue

      // check balance
      const balance = await cmContract.getBalance({ from: accounts[i] })
      let approve = i % 3 == 0

      if (!approve) {
        assert(balance.gt(VOTE_LOCKED_AMT.mul(new BN(2)))) // x2 because he previously got 1 batch unlocked by previous tie & approve
      }
    }
  })

  it('can withdraw all balance', async () => {
	for (let i = 0; i < minVote + 1; i++) {
		const beforebalance = await tokenContract.balanceOf(accounts[i])
		const unlocked = await cmContract.getBalance({from: accounts[i]})
		await cmContract.withdraw(unlocked, {from: accounts[i]})
		const afterBalance = await tokenContract.balanceOf(accounts[i])
		assert(afterBalance.sub(beforebalance).eq(unlocked))
	}
  })
})
