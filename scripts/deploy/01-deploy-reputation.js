const { deployContract, saveDeployment, loadDeployment, logSection } = require("../utils/helpers");
const { REPUTATION_NFT } = require("../utils/constants");

async function main() {
  logSection("DEPLOYING REPUTATION NFT");

  const [deployer] = await ethers.getSigners();
  console.log(`Deploying with account: ${deployer.address}`);
  
  const balance = await ethers.provider.getBalance(deployer.address);
  console.log(`Account balance: ${ethers.formatEther(balance)} ETH`);

  // Deploy ReputationNFT
  const reputationNFT = await deployContract(
    "ReputationNFT",
    deployer.address, // admin
    REPUTATION_NFT.BASE_URI
  );

  const deployments = loadDeployment(network.name);
  deployments.ReputationNFT = await reputationNFT.getAddress();
  
  await saveDeployment(network.name, deployments);

  console.log("\n✅ Reputation NFT deployment complete!");
  
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
