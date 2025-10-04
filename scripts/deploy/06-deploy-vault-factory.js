const { deployContract, saveDeployment, loadDeployment, logSection } = require("../utils/helpers");
const { VAULT_CONFIG } = require("../utils/constants");

async function main() {
  logSection("DEPLOYING TRADER VAULT FACTORY");

  const [deployer] = await ethers.getSigners();
  console.log(`Deploying with account: ${deployer.address}`);

  const deployments = loadDeployment(network.name);
  
  // Verify all dependencies
  if (!deployments.ReputationNFT) throw new Error("ReputationNFT not deployed");
  if (!deployments.TreasuryManager) throw new Error("TreasuryManager not deployed");
  if (!deployments.TradingVault) throw new Error("TradingVault not deployed");
  if (!deployments.OracleRegistry) throw new Error("OracleRegistry not deployed");
  if (!deployments.USDC) throw new Error("USDC not configured");

  // Deploy TraderVaultFactory
  const factory = await deployContract(
    "TraderVaultFactory",
    deployments.ReputationNFT,
    deployments.TreasuryManager,
    deployments.TradingVault,
    deployments.OracleRegistry,
    deployments.USDC,
    deployer.address
  );

  const factoryAddress = await factory.getAddress();

  // Configure default vault settings
  console.log("\nConfiguring default vault settings...");
  const tx = await factory.setDefaultConfig({
    initialCapital: VAULT_CONFIG.INITIAL_CAPITAL,
    maxPositionSize: VAULT_CONFIG.MAX_POSITION_SIZE,
    maxDailyLoss: VAULT_CONFIG.MAX_DAILY_LOSS,
    profitSplitBps: VAULT_CONFIG.PROFIT_SPLIT_BPS,
  });
  await tx.wait();
  console.log("✅ Default vault configuration set");

  // Authorize factory in TreasuryManager
  console.log("\nAuthorizing factory in TreasuryManager...");
  const treasury = await ethers.getContractAt("TreasuryManager", deployments.TreasuryManager);
  const authTx = await treasury.setVaultFactory(factoryAddress);
  await authTx.wait();
  console.log("✅ Factory authorized in Treasury");

  // Authorize factory to manage traders in TradingVault
  console.log("\nAuthorizing factory in TradingVault...");
  const tradingVault = await ethers.getContractAt("TradingVault", deployments.TradingVault);
  const authTx2 = await tradingVault.setAuthorizedManager(factoryAddress, true);
  await authTx2.wait();
  console.log("✅ Factory authorized in TradingVault");

  deployments.TraderVaultFactory = factoryAddress;
  await saveDeployment(network.name, deployments);

  console.log("\n✅ Trader Vault Factory deployment complete!");
  
  return deployments;
}

if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
}

module.exports = main;
