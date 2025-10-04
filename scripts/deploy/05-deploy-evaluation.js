const { deployContract, saveDeployment, loadDeployment, logSection } = require("../utils/helpers");
const { EVALUATION } = require("../utils/constants");

async function main() {
  logSection("DEPLOYING EVALUATION MANAGER");

  const [deployer] = await ethers.getSigners();
  console.log(`Deploying with account: ${deployer.address}`);

  const deployments = loadDeployment(network.name);
  
  // Verify dependencies
  if (!deployments.USDC) throw new Error("USDC not deployed");
  if (!deployments.OracleRegistry) throw new Error("OracleRegistry not deployed");
  if (!deployments.ReputationNFT) throw new Error("ReputationNFT not deployed");

  // Deploy EvaluationManager
  const evaluationManager = await deployContract(
    "EvaluationManager",
    deployments.USDC,
    deployments.OracleRegistry,
    deployments.ReputationNFT,
    deployer.address
  );

  const evaluationManagerAddress = await evaluationManager.getAddress();

  // Grant minting role to EvaluationManager
  console.log("\nGranting minting role to EvaluationManager...");
  const reputationNFT = await ethers.getContractAt("ReputationNFT", deployments.ReputationNFT);
  const MINTER_ROLE = await reputationNFT.MINTER_ROLE();
  
  let tx = await reputationNFT.grantRole(MINTER_ROLE, evaluationManagerAddress);
  await tx.wait();
  console.log("✅ Minting role granted");

  // Configure evaluation rules
  console.log("\nConfiguring evaluation rules...");
  tx = await evaluationManager.setEvaluationRules(
    EVALUATION.VIRTUAL_BALANCE,
    EVALUATION.PROFIT_TARGET_BPS,
    EVALUATION.MAX_DRAWDOWN_BPS,
    EVALUATION.MIN_TRADES,
    EVALUATION.EVALUATION_PERIOD,
    EVALUATION.EVALUATION_FEE
  );
  await tx.wait();
  console.log("✅ Evaluation rules configured");

  deployments.EvaluationManager = evaluationManagerAddress;
  await saveDeployment(network.name, deployments);

  console.log("\n✅ Evaluation Manager deployment complete!");
  
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
