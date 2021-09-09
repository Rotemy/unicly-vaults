const { ethers } = require("hardhat");

async function main() {
    const [ deployer ] = await ethers.getSigners();

    const uniclyXUnicVaultFactory = await ethers.getContractFactory("UniclyXUnicVault", deployer);
    const zapFactory = await ethers.getContractFactory("Zap", deployer);

    const uniclyXUnicVault = await uniclyXUnicVaultFactory.deploy();
    await uniclyXUnicVault.deployed();
    await uniclyXUnicVault.initialize(deployer.address);

    const zap = await zapFactory.deploy();
    await zap.deployed();
    await zap.initialize(uniclyXUnicVault.address);
}

main()
.then(() => process.exit(0))
.catch(error => {
  console.error(error);
  process.exit(1);
});
