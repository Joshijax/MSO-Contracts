require("@nomicfoundation/hardhat-toolbox");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    compilers: [
      {version: '0.7.6'},
      // {version: '0.8.20'},
    ],
    settings: {
      optimizer: {
        runs: 200,
        enabled: true
      }
    }
  },
};
