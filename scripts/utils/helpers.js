const fs = require("fs");
const path = require("path");

/**
 * Save deployment addresses to file
 */
async function saveDeployment(network, addresses) {
  const deploymentsDir = path.join(__dirname, "../../deployments");
  
  if (!fs.existsSync(deploymentsDir)) {
    fs.mkdirSync(deploymentsDir, { recursive: true });
  }

  const filePath = path.join(deploymentsDir, `${network}.json`);
  fs.writeFileSync(filePath, JSON.stringify(addresses, null, 2));
  
  console.log(`\n📝 Deployment addresses saved to: ${filePath}`);
}

/**
 * Load deployment addresses from file
 */
function loadDeployment(network) {
  const filePath = path.join(__dirname, "../../deployments", `${network}.json`);
  
  if (!fs.existsSync(filePath)) {
    return {};
  }

  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

/**
 * Wait for transaction confirmation with retries
 */
async function waitForTx(tx, confirmations = 2) {
  console.log(`⏳ Waiting for transaction: ${tx.hash}`);
  const receipt = await tx.wait(confirmations);
  console.log(`✅ Confirmed in block: ${receipt.blockNumber}`);
  return receipt;
}

/**
 * Deploy contract with retry logic
 */
async function deployContract(name, ...args) {
  console.log(`\n🚀 Deploying ${name}...`);
  
  const Contract = await ethers.getContractFactory(name);
  const contract = await Contract.deploy(...args);
  await contract.waitForDeployment();
  
  const address = await contract.getAddress();
  console.log(`✅ ${name} deployed to: ${address}`);
  
  return contract;
}

/**
 * Verify contract on block explorer
 */
async function verifyContract(address, constructorArguments) {
  console.log(`\n🔍 Verifying contract at: ${address}`);
  
  try {
    await hre.run("verify:verify", {
      address: address,
      constructorArguments: constructorArguments,
    });
    console.log(`✅ Contract verified`);
  } catch (error) {
    if (error.message.includes("Already Verified")) {
      console.log(`ℹ️  Contract already verified`);
    } else {
      console.log(`❌ Verification failed: ${error.message}`);
    }
  }
}

/**
 * Format large numbers for display
 */
function formatUnits(value, decimals = 6) {
  return ethers.formatUnits(value, decimals);
}

/**
 * Sleep for specified milliseconds
 */
function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Log section header
 */
function logSection(title) {
  console.log("\n" + "=".repeat(60));
  console.log(`  ${title}`);
  console.log("=".repeat(60));
}

/**
 * Log deployment info
 */
function logDeploymentInfo(deployments) {
  logSection("DEPLOYMENT SUMMARY");
  
  for (const [name, address] of Object.entries(deployments)) {
    console.log(`${name.padEnd(25)} : ${address}`);
  }
  
  console.log("=".repeat(60) + "\n");
}

/**
 * Check if address is valid
 */
function isValidAddress(address) {
  try {
    return ethers.isAddress(address);
  } catch {
    return false;
  }
}

module.exports = {
  saveDeployment,
  loadDeployment,
  waitForTx,
  deployContract,
  verifyContract,
  formatUnits,
  sleep,
  logSection,
  logDeploymentInfo,
  isValidAddress,
};
