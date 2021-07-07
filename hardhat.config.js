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
  defaultNetwork: "local",
  networks: {
    local: {
      url: "http://localhost:8545",
      timeout: 100000
    }
  },
  abiExporter: {
    flat: true
  }
};
