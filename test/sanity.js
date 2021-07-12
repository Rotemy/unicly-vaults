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
    await uniclyXUnicVault.initialize();

    // purchase UNIC
    const unicswapRouter = new ethers.Contract(unicswapRouterAddress, unicswapRouterAbi, owner);
    unicToken = new ethers.Contract(unicAddress, erc20Abi, owner);
    xUnicToken = new ethers.Contract(xUnicAddress, erc20Abi, owner);
    unicEthLpToken = new ethers.Contract(unicEthLpAddress, erc20Abi, addr1);
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
    await unicToken.approve(unicswapRouterAddress, ethers.utils.parseEther("10000"));
    await unicswapRouter.addLiquidityETH(
      unicAddress,
      ethers.utils.parseEther("20"),
      "1",
      "1",
      addr1.address,
      deadline,
      { value: ethers.utils.parseEther("2") }
    );
    await unicswapRouter.addLiquidityETH(
      unicAddress,
      ethers.utils.parseEther("20"),
      "1",
      "1",
      addr2.address,
      deadline,
      { value: ethers.utils.parseEther("2") }
    );
  });

  describe("Staking rewards", function () {
    it("Should stake UNICETH-LP and have proper amount, rate", async function () {
      let userStakeInfo;
      const xUnicUnicBalance = await unicToken.balanceOf(xUnicAddress);
      const xUnicTotalSupply = await xUnicToken.totalSupply();
      const xUnicRate = xUnicUnicBalance.mul(ethers.utils.parseEther('1')).div(xUnicTotalSupply);
      userStakeInfo = await uniclyXUnicVault.userInfo(0, addr1.address);
      expect(userStakeInfo.amount.toString()).to.equal('0');
      await unicEthLpToken.approve(uniclyXUnicVault.address, ethers.utils.parseEther("10000"));
      await uniclyXUnicVault.connect(addr1).deposit(0, ethers.utils.parseEther("1"));
      userStakeInfo = await uniclyXUnicVault.userInfo(0, addr1.address);
      expect(userStakeInfo.amount.toString()).to.equal(ethers.utils.parseEther("1"));
      expect(userStakeInfo.xUNICRate.toString()).to.equal(xUnicRate.toString());
    });

    it("Rate should increase as xUnic pool grows", async function () {
      await unicToken.transfer(xUnicAddress, ethers.utils.parseEther("1"));
      await unicEthLpToken.connect(addr2).approve(uniclyXUnicVault.address, ethers.utils.parseEther("10000"));
      await uniclyXUnicVault.connect(addr2).deposit(0, ethers.utils.parseEther("1"));
      const user1StakeInfo = await uniclyXUnicVault.userInfo(0, addr1.address);
      const user2StakeInfo = await uniclyXUnicVault.userInfo(0, addr2.address);
      const rateDiff = user2StakeInfo.xUNICRate.sub(user1StakeInfo.xUNICRate);
      expect(rateDiff.toNumber()).to.be.at.least(1);
    });

    it("Should allow a user to withdraw all", async function () {
      const user1PrevUnicEthBalance = await unicEthLpToken.balanceOf(addr1.address);
      const user1PrevXUnicBalance = await xUnicToken.balanceOf(addr1.address);
      await uniclyXUnicVault.connect(addr1).withdraw(0, ethers.utils.parseEther("1"));
      const user1PostUnicEthBalance = await unicEthLpToken.balanceOf(addr1.address);
      const user1PostXUnicBalance = await xUnicToken.balanceOf(addr1.address);
      const user1StakeInfo = await uniclyXUnicVault.userInfo(0, addr1.address);
      expect(user1PostUnicEthBalance.sub(user1PrevUnicEthBalance)).to.equal(ethers.utils.parseEther("1"));
      expect(user1PostXUnicBalance.sub(user1PrevXUnicBalance).toNumber()).to.be.at.least(1);
      expect(user1StakeInfo.amount.toNumber()).to.equal(0);
    });

    it("Should allow a user to partially withdraw", async function () {
    });

  });
});
