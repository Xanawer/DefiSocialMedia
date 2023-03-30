const truffleAssert = require('truffle-assertions')
const assert = require('assert')

const User = artifacts.require('User')

contract('User contract', function (accounts) {
  let userContract
  const creator = accounts[1]
  const follower1 = accounts[2]
  before(async () => {
    userContract = await User.deployed()
  })

  it('should create user', async () => {
    const name = 'test user 1'

    const tx = await userContract.createUser(name, 24, { from: creator })
    truffleAssert.eventEmitted(
      tx,
      'UserCreated',
      (e) => e.userAddress == creator
    )
    const profile1 = await userContract.getProfile({ from: creator })
    assert.strictEqual(profile1.addr, creator)
    assert.strictEqual(profile1.name, name)
  })

  it('should not allow duplicate user', async () => {
    const name = 'test user 1'
    await truffleAssert.reverts(userContract.createUser(name, 24, { from: creator }))
  })

  it('can follow user when not private', async () => {
    const name = 'test user 2'
    await userContract.createUser(name, 24, { from: follower1 })
    // user 2 folllow user 1
    await userContract.requestFollow(creator, { from: follower1 })
    assert.strictEqual(
      (await userContract.getFollowerCount(creator)).toNumber(),
      1
    )
    assert.ok(await userContract.isFollower(creator, follower1))
  })

  it('can unfollow', async () => {
    await userContract.unfollow(creator, { from: follower1 })
    assert.ok(!(await userContract.isFollower(creator, follower1)))
    assert.strictEqual(
     (await userContract.getFollowerCount(creator)).toNumber(),
      0
    )    
  })

  it('added to follow requests when private', async () => {
    await userContract.privateAccount({ from: creator })
    assert.ok(await userContract.isPrivateAccount(creator))
    // user 2 request to folllow user 1
    await userContract.requestFollow(creator, { from: follower1 })
    assert.ok(!(await userContract.isFollower(creator, follower1)))
    assert.ok(
      await userContract.requestedToFollow(creator, { from: follower1 })
    )
  })

  it('can accept follower', async () => {
    await userContract.acceptFollower(follower1, { from: creator })
    assert.ok(await userContract.isFollower(creator, follower1))
    assert.ok(
      !(await userContract.requestedToFollow(creator, { from: follower1 }))
    )
  })

  it('can delete account', async () => {
    await userContract.deleteUser({from: creator})
    await truffleAssert.reverts(userContract.getProfile())
  })  
})
