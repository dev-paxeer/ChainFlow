// Deployment constants and configuration

module.exports = {
  // Network configurations
  NETWORKS: {
    PAXEER: {
      chainId: 80000,
      name: "Paxeer Network",
    },
    LOCALHOST: {
      chainId: 1337,
      name: "Localhost",
    },
  },

  // Token addresses (update based on network)
  TOKENS: {
    USDC: {
      PAXEER: process.env.USDC || "0x17070D3E350fe9fDda071538840805eF813D4a37",
      LOCALHOST: "", // Will be deployed in tests
    },
  },

  // Evaluation configuration
  EVALUATION: {
    VIRTUAL_BALANCE: ethers.parseUnits("10000", 6), // 10,000 USDC
    PROFIT_TARGET_BPS: 1000, // 10%
    MAX_DRAWDOWN_BPS: 500, // 5%
    MIN_TRADES: 5,
    EVALUATION_PERIOD: 30 * 24 * 60 * 60, // 30 days
    EVALUATION_FEE: ethers.parseUnits("100", 6), // 100 USDC
  },

  // Vault configuration
  VAULT_CONFIG: {
    INITIAL_CAPITAL: ethers.parseUnits("100000", 6), // 100,000 USDC
    MAX_POSITION_SIZE: ethers.parseUnits("10000", 6), // 10,000 USDC
    MAX_DAILY_LOSS: ethers.parseUnits("2000", 6), // 2,000 USDC
    PROFIT_SPLIT_BPS: 8000, // 80% to trader, 20% to firm
  },

  // Oracle configuration
  ORACLES: {
    MAX_DEVIATION_BPS: 500, // 5%
    HEARTBEAT_TIMEOUT: 60, // 60 seconds
    MIN_UPDATE_INTERVAL: 1, // 1 second
    INITIAL_PRICES: {
      "BTC/USD": ethers.parseUnits("50000", 8),
      "ETH/USD": ethers.parseUnits("3000", 8),
      "EUR/USD": ethers.parseUnits("1.1", 8),
      "GBP/USD": ethers.parseUnits("1.3", 8),
    },
  },

  // Trading vault configuration
  TRADING_VAULT: {
    MAX_EXPOSURE_RATIO_BPS: 8000, // 80%
    MIN_COLLATERAL_RATIO_BPS: 12000, // 120%
  },

  // Reputation NFT
  REPUTATION_NFT: {
    BASE_URI: "https://api.chainprop.io/metadata/",
  },

  // Gas settings
  GAS: {
    LIMIT: 8000000,
    PRICE: ethers.parseUnits("20", "gwei"),
  },
};
