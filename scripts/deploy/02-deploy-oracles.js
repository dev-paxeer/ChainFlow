const { deployContract, saveDeployment, loadDeployment, logSection } = require("../utils/helpers");
const { ORACLES } = require("../utils/constants");

async function main() {
  logSection("DEPLOYING ORACLE INFRASTRUCTURE");

  const [deployer] = await ethers.getSigners();
  console.log(`Deploying with account: ${deployer.address}`);

  // Deploy OracleRegistry
  const oracleRegistry = await deployContract(
    "OracleRegistry",
    deployer.address
  );

  const oracleRegistryAddress = await oracleRegistry.getAddress();

  // Deploy price oracles for each asset
  const oracles = {};
  
  for (const [symbol, initialPrice] of Object.entries(ORACLES.INITIAL_PRICES)) {
    console.log(`\nDeploying oracle for ${symbol}...`);
    
    const oracle = await deployContract(
      "PriceOracle",
      symbol,
      initialPrice,
      deployer.address
    );

    const oracleAddress = await oracle.getAddress();
    oracles[symbol] = oracleAddress;

    // Configure oracle
    console.log(`Configuring ${symbol} oracle...`);
    let tx = await oracle.setMaxDeviation(ORACLES.MAX_DEVIATION_BPS);
    await tx.wait();
    
    tx = await oracle.setHeartbeatTimeout(ORACLES.HEARTBEAT_TIMEOUT);
    await tx.wait();
    
    tx = await oracle.setMinUpdateInterval(ORACLES.MIN_UPDATE_INTERVAL);
    await tx.wait();

    // Authorize deployer as price feeder
    tx = await oracle.setAuthorizedFeeder(deployer.address, true);
    await tx.wait();

    // Register in OracleRegistry
    console.log(`Registering ${symbol} in registry...`);
    tx = await oracleRegistry.registerOracle(symbol, oracleAddress);
    await tx.wait();

    console.log(`✅ ${symbol} oracle configured and registered`);
  }

  // Save deployments
  const deployments = loadDeployment(network.name);
  deployments.OracleRegistry = oracleRegistryAddress;
  deployments.Oracles = oracles;
  
  await saveDeployment(network.name, deployments);

  console.log("\n✅ Oracle infrastructure deployment complete!");
  
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
