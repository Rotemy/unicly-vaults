const {expect} = require("chai");

const unicswapRouterAbi = require('../abi/IUnicSwapRouter.json');
const erc20Abi = require('../abi/IERC20.json');
const unicswapRouterAddress = "0xE6E90bC9F3b95cdB69F48c7bFdd0edE1386b135a";
const unicAddress = "0x94e0bab2f6ab1f19f4750e42d7349f2740513ad5";
const xUnicAddress = "0xA62fB0c2Fb3C7b27797dC04e1fEA06C0a2Db919a";
const wethAddress = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2";
const unicEthLpAddress = "0x314D7DB4ba98D28B2356725b257bA4b0D675f165";
const uAPEToken = "0x17e347aad89B30b96557BCBfBff8a14e75CC88a1";
const uAPELPToken = "0xDC806458b80C608870b9621604199dc4c0F6A470";

describe("UniclyXUnicVault", function () {

    let uniclyFarmV3DoHardWorkExecutor;
    const v3 = "0x07306aCcCB482C8619e7ed119dAA2BDF2b4389D0";
    let uniclyXUnicVault;
    let unicToken;
    let xUnicToken;
    let unicEthLpToken;
    let owner;
    let addr1;
    let addr2;
    let addr3;
    let addr4;
    let addrs;
    let deadline;
    let unicswapRouter;

    before(async function () {
        const UniclyFarmV3DoHardWorkExecutorFactory = await ethers.getContractFactory("UniclyFarmV3DoHardWorkExecutor");
        uniclyFarmV3DoHardWorkExecutor = await UniclyFarmV3DoHardWorkExecutorFactory.deploy();
        await uniclyFarmV3DoHardWorkExecutor.deployed();
        const uniclyXUnicVaultFactory = await ethers.getContractFactory("UniclyXUnicVault");
        [owner, addr1, addr2, addr3, addr4, ...addrs] = await ethers.getSigners();
        uniclyXUnicVault = await uniclyXUnicVaultFactory.deploy();
        await uniclyXUnicVault.deployed();
        await uniclyXUnicVault.initialize(owner.address);

        // purchase UNIC
        unicswapRouter = new ethers.Contract(unicswapRouterAddress, unicswapRouterAbi, owner);
        unicToken = new ethers.Contract(unicAddress, erc20Abi, owner);
        xUnicToken = new ethers.Contract(xUnicAddress, erc20Abi, owner);
        unicEthLpToken = new ethers.Contract(unicEthLpAddress, erc20Abi, addr1);
        deadline = new Date().getTime() + 60 * 60 * 1000;
        await unicswapRouter.swapExactETHForTokens(
            '1',
            [wethAddress, unicAddress],
            owner.address,
            deadline,
            {value: ethers.utils.parseEther("100")}
        );
        await unicToken.approve(unicswapRouterAddress, ethers.utils.parseEther("10000"));
        await unicswapRouter.addLiquidityETH(
            unicAddress,
            ethers.utils.parseEther("20"),
            "1",
            "1",
            addr1.address,
            deadline,
            {value: ethers.utils.parseEther("2")}
        );
        await unicswapRouter.addLiquidityETH(
            unicAddress,
            ethers.utils.parseEther("20"),
            "1",
            "1",
            addr2.address,
            deadline,
            {value: ethers.utils.parseEther("2")}
        );
        await unicswapRouter.addLiquidityETH(
            unicAddress,
            ethers.utils.parseEther("20"),
            "1",
            "1",
            addr4.address,
            deadline,
            {value: ethers.utils.parseEther("2")}
        );
    });

    describe("Do hard work", function () {

        it("Should harvest rewards above 4 unic", async function () {

            const previousBalance = await xUnicToken.balanceOf(v3);
            console.log(previousBalance.toString());

            uniclyFarmV3DoHardWorkExecutor.doHardWork(ethers.utils.parseEther("4"));

            console.log((await xUnicToken.balanceOf(v3)).toString());
            expect((await xUnicToken.balanceOf(v3))).to.be.gt(previousBalance);
        });

        it("Should harvest rewards above 1 unic", async function () {

            const previousBalance = await xUnicToken.balanceOf(v3);
            console.log(previousBalance.toString());

            uniclyFarmV3DoHardWorkExecutor.doHardWork(ethers.utils.parseEther("1"));

            console.log((await xUnicToken.balanceOf(v3)).toString());
            expect((await xUnicToken.balanceOf(v3))).to.be.gt(previousBalance);
        });

        it("Shouldn't harvest rewards above 100 unic", async function () {

            const previousBalance = await xUnicToken.balanceOf(v3);
            console.log(previousBalance.toString());

            uniclyFarmV3DoHardWorkExecutor.doHardWork(ethers.utils.parseEther("100"));

            console.log((await xUnicToken.balanceOf(v3)).toString());
            expect((await xUnicToken.balanceOf(v3))).to.be.eq(previousBalance);
        });

    });

    describe("Staking rewards", function () {

        const UNIC_ETH_POOL_ID = 0;
        const uAPE_ETH_POOL_ID = 21;

        it("Should stake UNICETH-LP and have proper amount", async function () {
            let user1StakeInfo, user2StakeInfo;
            user1StakeInfo = await uniclyXUnicVault.userInfo(UNIC_ETH_POOL_ID, addr1.address);
            expect(user1StakeInfo.amount.toString()).to.equal('0');
            await unicEthLpToken.approve(uniclyXUnicVault.address, ethers.utils.parseEther("10000"));
            await unicEthLpToken.connect(addr2).approve(uniclyXUnicVault.address, ethers.utils.parseEther("10000"));
            await uniclyXUnicVault.connect(addr1).deposit(UNIC_ETH_POOL_ID, ethers.utils.parseEther("2"));
            await uniclyXUnicVault.connect(addr2).deposit(UNIC_ETH_POOL_ID, ethers.utils.parseEther("1"));
            user1StakeInfo = await uniclyXUnicVault.userInfo(UNIC_ETH_POOL_ID, addr1.address);
            user2StakeInfo = await uniclyXUnicVault.userInfo(UNIC_ETH_POOL_ID, addr2.address);
            expect(user1StakeInfo.amount.toString()).to.equal(ethers.utils.parseEther("2"));
            expect(user2StakeInfo.amount.toString()).to.equal(ethers.utils.parseEther("1"));
        });

        it("Should allow a user to withdraw all", async function () {
            const user1PrevUnicEthBalance = await unicEthLpToken.balanceOf(addr1.address);
            const user1PrevXUnicBalance = await xUnicToken.balanceOf(addr1.address);
            await uniclyXUnicVault.connect(addr1).withdraw(UNIC_ETH_POOL_ID, ethers.utils.parseEther("2"));
            const user1PostUnicEthBalance = await unicEthLpToken.balanceOf(addr1.address);
            const user1PostXUnicBalance = await xUnicToken.balanceOf(addr1.address);
            const user1StakeInfo = await uniclyXUnicVault.userInfo(UNIC_ETH_POOL_ID, addr1.address);
            expect(user1PostUnicEthBalance.sub(user1PrevUnicEthBalance)).to.equal(ethers.utils.parseEther("2"));
            expect(user1PostXUnicBalance.sub(user1PrevXUnicBalance).toNumber()).to.be.at.least(1);
            expect(user1StakeInfo.amount.toNumber()).to.equal(UNIC_ETH_POOL_ID);
        });

        it("Should allow a user to partially withdraw", async function () {
            const user2PrevUnicEthBalance = await unicEthLpToken.balanceOf(addr2.address);
            const user2PrevXUnicBalance = await xUnicToken.balanceOf(addr2.address);
            await uniclyXUnicVault.connect(addr2).withdraw(UNIC_ETH_POOL_ID, ethers.utils.parseEther("0.1"));
            const user2PostUnicEthBalance = await unicEthLpToken.balanceOf(addr2.address);
            const user2PostXUnicBalance = await xUnicToken.balanceOf(addr2.address);
            const user2StakeInfo = await uniclyXUnicVault.userInfo(UNIC_ETH_POOL_ID, addr2.address);
            expect(user2PostUnicEthBalance.sub(user2PrevUnicEthBalance)).to.equal(ethers.utils.parseEther("0.1"));
            expect(user2PostXUnicBalance.sub(user2PrevXUnicBalance).toNumber()).to.be.at.least(1);
            expect(user2StakeInfo.amount).to.equal(ethers.utils.parseEther("0.9"));
        });

        it("Should reward user with xUNIC", async () => {
            const user1StakeInfo = await uniclyXUnicVault.userInfo(uAPE_ETH_POOL_ID, addr3.address);
            expect(user1StakeInfo.amount).to.equal(0);
            await unicswapRouter.swapExactETHForTokens(
                '1',
                [wethAddress, uAPEToken],
                owner.address,
                deadline,
                {value: ethers.utils.parseEther("100")}
            );
            const uAPEContract = new ethers.Contract(uAPEToken, erc20Abi, owner);
            await uAPEContract.approve(unicswapRouterAddress, ethers.utils.parseEther("10000000000000"));
            await unicswapRouter.addLiquidityETH(
                uAPEToken,
                ethers.utils.parseEther("20000"),
                "1",
                "1",
                addr3.address,
                deadline,
                {value: ethers.utils.parseEther("100")}
            );
            const uAPELPTokenContract = new ethers.Contract(uAPELPToken, erc20Abi, addr3);
            const uAPELPTokenBalance = await uAPELPTokenContract.balanceOf(addr3.address);
            expect(uAPELPTokenBalance).to.be.gt(0);
            await uAPELPTokenContract.connect(addr3).approve(uniclyXUnicVault.address, ethers.utils.parseEther("10000"));
            await uniclyXUnicVault.connect(addr3).deposit(uAPE_ETH_POOL_ID, uAPELPTokenBalance);
            const userStakeInfo = await uniclyXUnicVault.userInfo(uAPE_ETH_POOL_ID, addr3.address);
            expect(userStakeInfo.amount).to.equal(uAPELPTokenBalance);
            expect(await xUnicToken.balanceOf(addr3.address)).to.equal(0);
            let pendingxUNICs = await uniclyXUnicVault.pendingxUNICs(uAPE_ETH_POOL_ID, addr3.address);
            expect(pendingxUNICs).to.equal(0);
            const day = 60 * 60 * 24;
            await advanceTime(day);
            pendingxUNICs = await uniclyXUnicVault.pendingxUNICs(uAPE_ETH_POOL_ID, addr3.address);
            expect(pendingxUNICs).to.be.gt(0);
            await uniclyXUnicVault.connect(addr3).deposit(uAPE_ETH_POOL_ID, 0);
            pendingxUNICs = await uniclyXUnicVault.pendingxUNICs(uAPE_ETH_POOL_ID, addr3.address);
            expect(pendingxUNICs).to.equal(0);
            expect(await xUnicToken.balanceOf(addr3.address)).to.be.gt(0);
        });

        it("Emergency withdraw", async () => {
            const user2StakeInfo = await uniclyXUnicVault.userInfo(UNIC_ETH_POOL_ID, addr2.address);
            const lpTokenAmount = user2StakeInfo.amount;
            const prevLPTokenAmount = await unicEthLpToken.balanceOf(addr2.address);
            await uniclyXUnicVault.connect(addr2).emergencyWithdraw(UNIC_ETH_POOL_ID);
            expect((await unicEthLpToken.balanceOf(addr2.address)).sub(prevLPTokenAmount)).to.equal(lpTokenAmount);
        });

        it("Do hard work", async () => {
            await advanceTime(60 * 60 * 13); // 13 hours
            await unicEthLpToken.connect(addr4).approve(uniclyXUnicVault.address, ethers.utils.parseEther("10000"));
            await uniclyXUnicVault.connect(addr4).deposit(UNIC_ETH_POOL_ID, ethers.utils.parseEther("2"));
            const result = await uniclyXUnicVault.doHardWork();
            const transaction = await ethers.provider.getTransactionReceipt(result.hash);
            let numberOfUpdatedPools = -1;
            transaction.logs.forEach(log => {
                if (log.topics[0] === '0x43e9e58d899d0850c765e9c263078f0d32b15e35e2c1c63c94e94d2daf54ce89') {
                    numberOfUpdatedPools = parseInt(log.data, 16);
                }
            });
            expect(numberOfUpdatedPools).to.equal(1);
        });
    });
});

function hre() {
    return require("hardhat");
}

function network() {
    return hre().network;
}

async function advanceTime(seconds) {
    console.log(`advancing time by ${seconds} seconds`);
    const startBlock = await ethers.provider.getBlockNumber();
    const startBlockTime = (await ethers.provider.getBlock(startBlock)).timestamp;

    const secondsPerBlock = 13;
    const blocks = Math.round(seconds / secondsPerBlock);
    for (let i = 0; i < blocks; i++) {
        await network().provider.send("evm_increaseTime", [secondsPerBlock]);
        await network().provider.send("evm_mine", [1 + startBlockTime + secondsPerBlock * i]);
    }
    const nowBlock = await ethers.provider.getBlockNumber();
    console.log("was block", startBlock.toFixed(), "now block", nowBlock);
    console.log(
        "was block time",
        startBlockTime.toFixed(),
        "now block time",
        (await ethers.provider.getBlock(nowBlock)).timestamp
    );
}
