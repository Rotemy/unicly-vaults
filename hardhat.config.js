require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-ethers");
require("hardhat-abi-exporter");

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.6.12",
        settings: {
          optimizer: {
            enabled: true,
            runs: 2000
          }
        }
      },
    ]
  }, 
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      forking: {
        blockNumber: 12846192,
        url: "https://eth-mainnet.alchemyapi.io/v2/T2CqQfiMJI3yJa1BTnfQfPG6hcfir7Tn"// TODO + configFile().alchemyKey,
      },
      blockGasLimit: 12e6
    },
  },
  mocha: {
    timeout: 120000,
    retries: 0,
    bail: true,
  },
  abiExporter: {
    flat: true
  }
};
