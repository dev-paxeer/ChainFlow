const { deployContract, saveDeployment, loadDeployment, logSection } = require("../utils/helpers");
const { TRADING_VAULT } = require("../utils/constants");

async function main() {
  logSection("DEPLOYING TRADING VAULT");

  const [deployer] = await ethers.getSigners();
  console.log(`Deploying with account: ${deployer.address}`);

  const deployments = loadDeployment(network.name);
  
  if (!deployments.USDC) {
    throw new Error("USDC address not found. Run 03-deploy-treasury.js first");
  }

  // Deploy TradingVault
  const tradingVault = await deployContract(
    "TradingVault",
    deployments.USDC,
    deployer.address
  );

  const tradingVaultAddress = await tradingVault.getAddress();

  // Configure exposure and collateral ratios
  console.log("\nConfiguring Trading Vault...");
  
  let tx = await tradingVault.setMaxExposureRatio(TRADING_VAULT.MAX_EXPOSURE_RATIO_BPS);
  await tx.wait();
  console.log(`✅ Max exposure ratio set to ${TRADING_VAULT.MAX_EXPOSURE_RATIO_BPS / 100}%`);
  
  tx = await tradingVault.setMinCollateralRatio(TRADING_VAULT.MIN_COLLATERAL_RATIO_BPS);
  await tx.wait();
  console.log(`✅ Min collateral ratio set to ${TRADING_VAULT.MIN_COLLATERAL_RATIO_BPS / 100}%`);

  deployments.TradingVault = tradingVaultAddress;
  await saveDeployment(network.name, deployments);

  console.log("\n✅ Trading Vault deployment complete!");
  
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
