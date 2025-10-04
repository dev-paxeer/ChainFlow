const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Full Lifecycle Integration Test", function () {
  let usdc;
  let oracleRegistry, btcOracle, ethOracle;
  let reputationNFT;
  let treasury;
  let tradingVault;
  let evaluationManager;
  let vaultFactory;
  let owner, trader, priceFeeder;

  const USDC_DECIMALS = 6;
  const INITIAL_BTC_PRICE = ethers.parseUnits("50000", 8);
  const INITIAL_ETH_PRICE = ethers.parseUnits("3000", 8);

  before(async function () {
    this.timeout(60000);
    [owner, trader, priceFeeder] = await ethers.getSigners();

    console.log("\n🚀 Deploying complete system...");

    // Deploy USDC
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    usdc = await MockERC20.deploy("USD Coin", "USDC", USDC_DECIMALS);
    await usdc.waitForDeployment();
    console.log("✅ USDC deployed");

    // Mint USDC to participants
    await usdc.mint(trader.address, ethers.parseUnits("10000", USDC_DECIMALS));
    await usdc.mint(owner.address, ethers.parseUnits("1000000", USDC_DECIMALS));

    // Deploy Oracle Infrastructure
    const OracleRegistry = await ethers.getContractFactory("OracleRegistry");
    oracleRegistry = await OracleRegistry.deploy(owner.address);
    await oracleRegistry.waitForDeployment();

    const PriceOracle = await ethers.getContractFactory("PriceOracle");
    btcOracle = await PriceOracle.deploy("BTC/USD", INITIAL_BTC_PRICE, owner.address);
    await btcOracle.waitForDeployment();
    await btcOracle.setAuthorizedFeeder(priceFeeder.address, true);

    ethOracle = await PriceOracle.deploy("ETH/USD", INITIAL_ETH_PRICE, owner.address);
    await ethOracle.waitForDeployment();
    await ethOracle.setAuthorizedFeeder(priceFeeder.address, true);

    await oracleRegistry.registerOracle("BTC/USD", await btcOracle.getAddress());
    await oracleRegistry.registerOracle("ETH/USD", await ethOracle.getAddress());
    console.log("✅ Oracles deployed");

    // Deploy ReputationNFT
    const ReputationNFT = await ethers.getContractFactory("ReputationNFT");
    reputationNFT = await ReputationNFT.deploy(owner.address, "https://api.test/");
    await reputationNFT.waitForDeployment();
    console.log("✅ ReputationNFT deployed");

    // Deploy Treasury
    const TreasuryManager = await ethers.getContractFactory("TreasuryManager");
    treasury = await TreasuryManager.deploy(await usdc.getAddress(), owner.address);
    await treasury.waitForDeployment();
    console.log("✅ Treasury deployed");

    // Fund treasury
    await usdc.connect(owner).approve(await treasury.getAddress(), ethers.parseUnits("1000000", USDC_DECIMALS));
    await treasury.connect(owner).depositCapital(ethers.parseUnits("500000", USDC_DECIMALS));

    // Deploy TradingVault
    const TradingVault = await ethers.getContractFactory("TradingVault");
    tradingVault = await TradingVault.deploy(await usdc.getAddress(), owner.address);
    await tradingVault.waitForDeployment();
    console.log("✅ TradingVault deployed");

    // Fund trading vault
    await usdc.connect(owner).approve(await tradingVault.getAddress(), ethers.parseUnits("200000", USDC_DECIMALS));
    await tradingVault.connect(owner).deposit(ethers.parseUnits("200000", USDC_DECIMALS));

    // Deploy EvaluationManager
    const EvaluationManager = await ethers.getContractFactory("EvaluationManager");
    evaluationManager = await EvaluationManager.deploy(
      await usdc.getAddress(),
      await oracleRegistry.getAddress(),
      await reputationNFT.getAddress(),
      owner.address
    );
    await evaluationManager.waitForDeployment();

    const MINTER_ROLE = await reputationNFT.MINTER_ROLE();
    await reputationNFT.grantRole(MINTER_ROLE, await evaluationManager.getAddress());
    console.log("✅ EvaluationManager deployed");

    // Deploy VaultFactory
    const TraderVaultFactory = await ethers.getContractFactory("TraderVaultFactory");
    vaultFactory = await TraderVaultFactory.deploy(
      await reputationNFT.getAddress(),
      await treasury.getAddress(),
      await tradingVault.getAddress(),
      await oracleRegistry.getAddress(),
      await usdc.getAddress(),
      owner.address
    );
    await vaultFactory.waitForDeployment();

    await treasury.setVaultFactory(await vaultFactory.getAddress());
    
    // Authorize factory to manage traders on TradingVault
    await tradingVault.setAuthorizedManager(await vaultFactory.getAddress(), true);
    
    console.log("✅ VaultFactory deployed\n");
  });

  describe("Complete User Journey: Evaluation → Funding → Trading → Profit", function () {
    let traderVaultAddress;

    it("Step 1: Trader starts evaluation", async function () {
      const fee = ethers.parseUnits("100", USDC_DECIMALS);
      await usdc.connect(trader).approve(await evaluationManager.getAddress(), fee);
      await evaluationManager.connect(trader).startEvaluation();

      const eval = await evaluationManager.getEvaluation(trader.address);
      expect(eval.isActive).to.be.true;
      console.log("    ✅ Evaluation started");
    });

    it("Step 2: Trader executes 5 profitable trades", async function () {
      // Each 5000 USDC position with 5% price move generates 250 USDC profit
      // 5 trades * 250 = 1250 USDC profit (exceeds 1000 USDC target)
      const positionSizes = [5000, 5000, 5000, 5000, 5000]; // USDC
      
      for (let i = 0; i < 5; i++) {
        // Open position
        await evaluationManager.connect(trader).executeVirtualTrade(
          "BTC/USD",
          ethers.parseUnits(String(positionSizes[i]), USDC_DECIMALS),
          true
        );

        // Price increases by 5%
        const priceIncrease = (INITIAL_BTC_PRICE * BigInt(5)) / BigInt(100);
        const newPrice = INITIAL_BTC_PRICE + priceIncrease;
        await btcOracle.connect(priceFeeder).updatePrice(newPrice);

        // Close position
        await evaluationManager.connect(trader).closeVirtualTrade(i + 1);
        
        // Reset price
        await btcOracle.connect(priceFeeder).updatePrice(INITIAL_BTC_PRICE);
      }

      const eval = await evaluationManager.getEvaluation(trader.address);
      expect(eval.passed).to.be.true;
      console.log("    ✅ Completed 5 profitable trades");
    });

    it("Step 3: Trader receives Reputation NFT", async function () {
      expect(await reputationNFT.hasValidCredential(trader.address)).to.be.true;
      
      const tokenId = await reputationNFT.getTokenId(trader.address);
      const metadata = await reputationNFT.getMetadata(tokenId);
      
      console.log(`    ✅ NFT minted - Profit: ${ethers.formatUnits(metadata.profitAchieved, USDC_DECIMALS)} USDC`);
    });

    it("Step 4: Trader deploys funded vault", async function () {
      await vaultFactory.connect(trader).deployVault();
      
      traderVaultAddress = await vaultFactory.getVaultByTrader(trader.address);
      expect(traderVaultAddress).to.not.equal(ethers.ZeroAddress);
      
      console.log(`    ✅ Vault deployed at: ${traderVaultAddress}`);
    });

    it("Step 5: Trader executes live trade with real capital", async function () {
      const traderVault = await ethers.getContractAt("TraderVault", traderVaultAddress);

      // Ensure balance is synced
      await traderVault.syncBalance();
      
      const statsBefore = await traderVault.getVaultStats();
      console.log(`    Balance before trade: ${ethers.formatUnits(statsBefore.balance, USDC_DECIMALS)} USDC`);

      // Execute live long trade on BTC
      await traderVault.connect(trader).executeLiveTrade(
        "BTC/USD",
        ethers.parseUnits("1000", USDC_DECIMALS), // $1000 position
        true, // long
        INITIAL_BTC_PRICE - ethers.parseUnits("2000", 8), // stop loss
        INITIAL_BTC_PRICE + ethers.parseUnits("5000", 8)  // take profit
      );

      const stats = await traderVault.getVaultStats();
      console.log(`    ✅ Live trade executed - Balance: ${ethers.formatUnits(stats.balance, USDC_DECIMALS)} USDC`);
    });

    it("Step 6: Price moves favorably, trader closes with profit", async function () {
      const traderVault = await ethers.getContractAt("TraderVault", traderVaultAddress);

      // Price increases 5% (within oracle deviation limit)
      const priceIncrease = (INITIAL_BTC_PRICE * BigInt(5)) / BigInt(100);
      const profitPrice = INITIAL_BTC_PRICE + priceIncrease;
      await btcOracle.connect(priceFeeder).updatePrice(profitPrice);

      // Close the position
      await traderVault.connect(trader).closeLiveTrade(1);

      const stats = await traderVault.getVaultStats();
      expect(stats.balance).to.be.gt(ethers.parseUnits("100000", USDC_DECIMALS));
      
      console.log(`    ✅ Position closed with profit - New balance: ${ethers.formatUnits(stats.balance, USDC_DECIMALS)} USDC`);
    });

    it("Step 7: Trader requests profit payout (80/20 split)", async function () {
      const traderVault = await ethers.getContractAt("TraderVault", traderVaultAddress);

      const statsBefore = await traderVault.getVaultStats();
      const availableProfit = statsBefore.profit;

      if (availableProfit > 0) {
        const traderBalanceBefore = await usdc.balanceOf(trader.address);

        await traderVault.connect(trader).requestPayout();

        const traderBalanceAfter = await usdc.balanceOf(trader.address);
        const traderReceived = traderBalanceAfter - traderBalanceBefore;

        // Should receive 80% of profit
        const expectedTraderShare = (availableProfit * 8000n) / 10000n;
        expect(traderReceived).to.be.closeTo(expectedTraderShare, ethers.parseUnits("1", USDC_DECIMALS));

        console.log(`    ✅ Payout executed - Trader received: ${ethers.formatUnits(traderReceived, USDC_DECIMALS)} USDC`);
      }
    });
  });

  describe("System Health Checks", function () {
    it("Should maintain proper accounting", async function () {
      const treasuryBalance = await treasury.getTreasuryBalance();
      const tradingVaultBalance = await usdc.balanceOf(await tradingVault.getAddress());
      
      console.log(`    Treasury Balance: ${ethers.formatUnits(treasuryBalance, USDC_DECIMALS)} USDC`);
      console.log(`    Trading Vault Balance: ${ethers.formatUnits(tradingVaultBalance, USDC_DECIMALS)} USDC`);
      
      expect(treasuryBalance).to.be.gt(0);
      expect(tradingVaultBalance).to.be.gt(0);
    });

    it("Should have valid oracle prices", async function () {
      const [btcPrice] = await oracleRegistry.getLatestPrice("BTC/USD");
      const [ethPrice] = await oracleRegistry.getLatestPrice("ETH/USD");
      
      expect(btcPrice).to.be.gt(0);
      expect(ethPrice).to.be.gt(0);
      
      console.log(`    BTC Price: $${ethers.formatUnits(btcPrice, 8)}`);
      console.log(`    ETH Price: $${ethers.formatUnits(ethPrice, 8)}`);
    });

    it("Should show correct vault count", async function () {
      const vaultCount = await vaultFactory.getVaultCount();
      expect(vaultCount).to.equal(1);
      
      console.log(`    Total Vaults Deployed: ${vaultCount}`);
    });
  });
});
