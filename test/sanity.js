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
    const unicEthLpToken = new ethers.Contract(unicEthLpAddress, erc20Abi, owner);
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

  // You can nest describe calls to create subsections.
  describe("Deployment", function () {
    it("Should assign the total supply of tokens to the owner", async function () {
      //const ownerBalance = await hardhatToken.balanceOf(owner.address);
      //expect(await hardhatToken.totalSupply()).to.equal(ownerBalance);
    });
  });

  describe("Staking rewards", function () {
    //it("Should transfer tokens between accounts", async function () {
      //// Transfer 50 tokens from owner to addr1
      //await hardhatToken.transfer(addr1.address, 50);
      //const addr1Balance = await hardhatToken.balanceOf(addr1.address);
      //expect(addr1Balance).to.equal(50);

      //// Transfer 50 tokens from addr1 to addr2
      //// We use .connect(signer) to send a transaction from another account
      //await hardhatToken.connect(addr1).transfer(addr2.address, 50);
      //const addr2Balance = await hardhatToken.balanceOf(addr2.address);
      //expect(addr2Balance).to.equal(50);
    //});
  });
});
