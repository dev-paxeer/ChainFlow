const { logSection, logDeploymentInfo } = require("../utils/helpers");

const deployReputationNFT = require("./01-deploy-reputation");
const deployOracles = require("./02-deploy-oracles");
const deployTreasury = require("./03-deploy-treasury");
const deployTradingVault = require("./04-deploy-trading-vault");
const deployEvaluation = require("./05-deploy-evaluation");
const deployVaultFactory = require("./06-deploy-vault-factory");

async function main() {
  logSection("CHAINPROP COMPLETE DEPLOYMENT");

  console.log(`Network: ${network.name}`);
  console.log(`Chain ID: ${network.config.chainId}`);

  const [deployer] = await ethers.getSigners();
  console.log(`Deployer: ${deployer.address}`);
  
  const balance = await ethers.provider.getBalance(deployer.address);
  console.log(`Balance: ${ethers.formatEther(balance)} ETH\n`);

  try {
    // Phase 1: Reputation System
    logSection("PHASE 1: REPUTATION SYSTEM");
    await deployReputationNFT();
    
    // Phase 2: Oracle Infrastructure
    logSection("PHASE 2: ORACLE INFRASTRUCTURE");
    await deployOracles();
    
    // Phase 3: Treasury
    logSection("PHASE 3: TREASURY MANAGEMENT");
    await deployTreasury();
    
    // Phase 4: Trading Vault
    logSection("PHASE 4: TRADING INFRASTRUCTURE");
    await deployTradingVault();
    
    // Phase 5: Evaluation System
    logSection("PHASE 5: EVALUATION SYSTEM");
    await deployEvaluation();
    
    // Phase 6: Vault Factory
    logSection("PHASE 6: TRADER VAULT FACTORY");
    const finalDeployments = await deployVaultFactory();

    // Display final summary
    logDeploymentInfo(finalDeployments);

    console.log("🎉 ALL CONTRACTS DEPLOYED SUCCESSFULLY! 🎉\n");
    console.log("Next steps:");
    console.log("1. Fund the TreasuryManager with USDC");
    console.log("2. Fund the TradingVault with collateral");
    console.log("3. Set up price feeder bots for oracles");
    console.log("4. Verify contracts on block explorer");
    console.log("5. Transfer ownership to multisig (if applicable)\n");

  } catch (error) {
    console.error("\n❌ Deployment failed!");
    console.error(error);
    process.exit(1);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
