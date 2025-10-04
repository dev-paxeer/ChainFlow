const { deployContract, saveDeployment, loadDeployment, logSection } = require("../utils/helpers");
const { TOKENS } = require("../utils/constants");

async function main() {
  logSection("DEPLOYING TREASURY MANAGER");

  const [deployer] = await ethers.getSigners();
  console.log(`Deploying with account: ${deployer.address}`);

  // Get USDC address for network
  const usdcAddress = TOKENS.USDC[network.name.toUpperCase()] || process.env.USDC;
  
  if (!usdcAddress) {
    throw new Error("USDC address not configured for this network");
  }

  console.log(`Using USDC at: ${usdcAddress}`);

  // Deploy TreasuryManager
  const treasury = await deployContract(
    "TreasuryManager",
    usdcAddress,
    deployer.address
  );

  const deployments = loadDeployment(network.name);
  deployments.TreasuryManager = await treasury.getAddress();
  deployments.USDC = usdcAddress;
  
  await saveDeployment(network.name, deployments);

  console.log("\n✅ Treasury Manager deployment complete!");
  
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
