require("@nomicfoundation/hardhat-toolbox");
require("@openzeppelin/hardhat-upgrades");
require("dotenv/config"); // Import and configure dotenv
require("@uniswap/hardhat-v3-deploy");

// Retrieve the private key and API keys from the .env file
const privateKey = process.env.PRIVATE_KEY;
const etherscanApiKey = process.env.ETHERSCAN_API_KEY;
const basescanApiKey = process.env.BASESCAN_API_KEY;

// Check if the private key is set
if (!privateKey) {
  console.warn("🚨 WARNING: PRIVATE_KEY is not set in the .env file. Deployments will not be possible.");
}

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.20",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.8.17",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.5.16",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.6.6",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      }
    ]
  },
  networks: {
    'paxeer-network': {
      url: 'https://v1-api.paxeer.app/rpc',
      chainId: 80000,
      accounts: privateKey ? [privateKey] : [],
      gasPrice: 20000000000, // 20 gwei
      gas: 8000000,
    },
    paxeer: {
      url: 'https://v1-api.paxeer.app/rpc',
      chainId: 80000,
      accounts: privateKey ? [privateKey] : [],
      gasPrice: 20000000000, // 20 gwei
      gas: 8000000,
    },
  },
  etherscan: {
    apiKey: {
      'paxeer-network': 'empty'
    },
    customChains: [
      {
        network: "paxeer-network",
        chainId: 80000,
        urls: {
          apiURL: "https://paxscan.paxeer.app:443/api",
          browserURL: "https://paxscan.paxeer.app:443"
        }
      }
    ]
  },
  sourcify: {
    enabled: true
  }
};
