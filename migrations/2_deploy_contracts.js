const AdsMarket = artifacts.require('AdsMarket')
const ContentModeration = artifacts.require('ContentModeration')
const ContentModerationStorage = artifacts.require('ContentModerationStorage')
const NFT = artifacts.require('NFT')
const Post= artifacts.require('Post')
const PostStorage = artifacts.require('PostStorage')
const RNG = artifacts.require('RNG')
const Token = artifacts.require('Token')
const User = artifacts.require('User')
const UserStorage = artifacts.require('UserStorage')
const Feed = artifacts.require('Feed')

module.exports = async (deployer, network, accounts) => {
  // deploy RNG, Token, NFT
  await deployer.deploy(RNG)
  await deployer.deploy(Token)
  await deployer.deploy(NFT)

  // deploy POST
  await deployer.deploy(PostStorage)
  await deployer.deploy(
    Post,
    RNG.address,
    NFT.address,
    Token.address,
    PostStorage.address
  )

  // deploy FEED
  await deployer.deploy(Feed, Post.address)

  // deploy USER
  await deployer.deploy(UserStorage)
  await deployer.deploy(User, Post.address, UserStorage.address)

  // deploy ADS
  await deployer.deploy(AdsMarket, Post.address, Token.address, User.address)

  // deploy CONTENT MODERATION
  await deployer.deploy(ContentModerationStorage)
  await deployer.deploy(
    ContentModeration,
    ContentModerationStorage.address,
    RNG.address,
    Post.address,
    Token.address,
    User.address
  )

  // initialize content moderation
  const cms = await ContentModerationStorage.deployed()
  await cms.init(ContentModeration.address)

  // initialize nft
  const nft = await NFT.deployed()
  await nft.init(Post.address)

  // initialize post
  const postStorage = await PostStorage.deployed()
  await postStorage.init(Post.address)
  const postLogic = await Post.deployed()
  await postLogic.init(
    User.address,
    Feed.address,
    AdsMarket.address,
    ContentModeration.address
  )

  // initialize user
  const userStorage = await UserStorage.deployed()
  await userStorage.init(User.address)

  // initialize token
  const token = await Token.deployed()
  await token.init(ContentModeration.address, AdsMarket.address)
}

