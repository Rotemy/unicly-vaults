const { expect } = require("chai");

const unicswapRouterAbi = require('../abi/IUnicSwapRouter.json');
const erc20Abi = require('../abi/IERC20.json');
const unicswapRouterAddress = "0xE6E90bC9F3b95cdB69F48c7bFdd0edE1386b135a";
const unicAddress = "0x94e0bab2f6ab1f19f4750e42d7349f2740513ad5";
const xUnicAddress = "0xA62fB0c2Fb3C7b27797dC04e1fEA06C0a2Db919a";
const wethAddress = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2";
const unicEthLpAddress = "0x314D7DB4ba98D28B2356725b257bA4b0D675f165";

describe("UniclyXUnicVault", function () {

  let uniclyXUnicVault;
  let unicToken;
  let xUnicToken;
  let unicEthLpToken;
  let owner;
  let addr1;
  let addr2;
  let addrs;

  before(async function () {
    const uniclyXUnicVaultFactory  = await ethers.getContractFactory("UniclyXUnicVault");
    [owner, addr1, addr2, ...addrs] = await ethers.getSigners();
    uniclyXUnicVault = await uniclyXUnicVaultFactory.deploy();
    await uniclyXUnicVault.deployed();

    // purchase UNIC
    const unicswapRouter = new ethers.Contract(unicswapRouterAddress, unicswapRouterAbi, owner);
    unicToken = new ethers.Contract(unicAddress, erc20Abi, owner);
    xUnicToken = new ethers.Contract(xUnicAddress, erc20Abi, owner);
    unicEthLpToken = new ethers.Contract(unicEthLpAddress, erc20Abi, addr1);
    const prevUnicBalance = await unicToken.balanceOf(owner.address);
    console.log(`prev UNIC balance: ${prevUnicBalance.toString()}`);
    const lastBlockNumber = await ethers.provider.getBlockNumber();
    const lastBlockTimestamp = (await ethers.provider.getBlock(lastBlockNumber)).timestamp;
    const deadline = String(lastBlockTimestamp + 1000000);
    await unicswapRouter.swapExactETHForTokens(
      '1',
      [wethAddress, unicAddress],
      owner.address,
      deadline,
      { value: ethers.utils.parseEther("100") }
    );
    const postUnicBalance = await unicToken.balanceOf(owner.address);
    console.log(`post UNIC balance: ${postUnicBalance.toString()}`);
    await unicToken.approve(unicswapRouterAddress, ethers.utils.parseEther("10000"));
    const prevUnicEthBalance = await unicEthLpToken.balanceOf(addr1.address);
    console.log(`prev UNICETH balance: ${prevUnicEthBalance.toString()}`);
    await unicswapRouter.addLiquidityETH(
      unicAddress,
      ethers.utils.parseEther("20"),
      "1",
      "1",
      addr1.address,
      deadline,
      { value: ethers.utils.parseEther("2") }
    );
    const postUnicEthBalance = await unicEthLpToken.balanceOf(addr1.address);
    console.log(`post UNICETH balance: ${postUnicEthBalance.toString()}`);
  });

  describe("Staking rewards", function () {
    it("Should stake UNICETH-LP", async function () {
      let userStakeInfo;
      userStakeInfo = await uniclyXUnicVault.userInfo(0, addr1.address);
      console.log(userStakeInfo);
      await unicEthLpToken.approve(uniclyXUnicVault.address, ethers.utils.parseEther("10000"));
      console.log(addr1.address);
      await uniclyXUnicVault.connect(addr1).deposit(0, ethers.utils.parseEther("1"));
      userStakeInfo = await uniclyXUnicVault.userInfo(0, addr1.address);
      console.log(userStakeInfo);
      //expect(addr1Balance).to.equal(50);
    });
  });
});
