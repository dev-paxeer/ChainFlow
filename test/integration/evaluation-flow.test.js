const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Evaluation Flow Integration", function () {
  let usdc;
  let oracleRegistry;
  let btcOracle;
  let reputationNFT;
  let evaluationManager;
  let owner, trader1, trader2;

  const INITIAL_BTC_PRICE = ethers.parseUnits("50000", 8);
  const VIRTUAL_BALANCE = ethers.parseUnits("10000", 6);
  const EVALUATION_FEE = ethers.parseUnits("100", 6);

  beforeEach(async function () {
    [owner, trader1, trader2] = await ethers.getSigners();

    // Deploy mock USDC
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    usdc = await MockERC20.deploy("USD Coin", "USDC", 6);
    await usdc.waitForDeployment();

    // Mint USDC to traders
    await usdc.mint(trader1.address, ethers.parseUnits("1000", 6));
    await usdc.mint(trader2.address, ethers.parseUnits("1000", 6));

    // Deploy OracleRegistry
    const OracleRegistry = await ethers.getContractFactory("OracleRegistry");
    oracleRegistry = await OracleRegistry.deploy(owner.address);
    await oracleRegistry.waitForDeployment();

    // Deploy BTC Oracle
    const PriceOracle = await ethers.getContractFactory("PriceOracle");
    btcOracle = await PriceOracle.deploy("BTC/USD", INITIAL_BTC_PRICE, owner.address);
    await btcOracle.waitForDeployment();

    // Configure oracle
    await btcOracle.setAuthorizedFeeder(owner.address, true);
    await btcOracle.setMaxDeviation(500); // 5%
    await btcOracle.setHeartbeatTimeout(60);

    // Register oracle
    await oracleRegistry.registerOracle("BTC/USD", await btcOracle.getAddress());

    // Deploy ReputationNFT
    const ReputationNFT = await ethers.getContractFactory("ReputationNFT");
    reputationNFT = await ReputationNFT.deploy(owner.address, "https://api.test.io/");
    await reputationNFT.waitForDeployment();

    // Deploy EvaluationManager
    const EvaluationManager = await ethers.getContractFactory("EvaluationManager");
    evaluationManager = await EvaluationManager.deploy(
      await usdc.getAddress(),
      await oracleRegistry.getAddress(),
      await reputationNFT.getAddress(),
      owner.address
    );
    await evaluationManager.waitForDeployment();

    // Grant minting role
    const MINTER_ROLE = await reputationNFT.MINTER_ROLE();
    await reputationNFT.grantRole(MINTER_ROLE, await evaluationManager.getAddress());

    // Configure evaluation rules
    await evaluationManager.setEvaluationRules(
      VIRTUAL_BALANCE,    // virtualBalance
      1000,               // profitTargetBps (10%)
      500,                // maxDrawdownBps (5%)
      5,                  // minTrades
      30 * 24 * 60 * 60,  // evaluationPeriod (30 days)
      EVALUATION_FEE      // evaluationFee
    );
  });

  describe("Complete Successful Evaluation", function () {
    it("Should allow trader to pass evaluation and receive NFT", async function () {
      // Approve USDC
      await usdc.connect(trader1).approve(await evaluationManager.getAddress(), EVALUATION_FEE);

      // Start evaluation
      await evaluationManager.connect(trader1).startEvaluation();
      
      let evaluation = await evaluationManager.getEvaluation(trader1.address);
      expect(evaluation.isActive).to.be.true;
      expect(evaluation.virtualBalance).to.equal(VIRTUAL_BALANCE);

      // Execute trades to generate >1000 USDC profit (need 11,000 total)
      // With 10x leverage and 5% price moves, each 5000 USDC position generates 250 USDC profit
      const positionSizes = [5000, 5000, 5000, 5000, 5000]; // USDC
      for (let i = 0; i < 5; i++) {
        // Open long position
        await evaluationManager.connect(trader1).executeVirtualTrade(
          "BTC/USD",
          ethers.parseUnits(String(positionSizes[i]), 6), // size in USDC
          true // isLong
        );

        // Update BTC price (increase by 5%)
        const priceIncrease = (INITIAL_BTC_PRICE * BigInt(5)) / BigInt(100); // 5% increase
        const newPrice = INITIAL_BTC_PRICE + priceIncrease;
        await btcOracle.updatePrice(newPrice);

        // Close position
        await evaluationManager.connect(trader1).closeVirtualTrade(i + 1);
        
        // Reset price for next trade
        await btcOracle.updatePrice(INITIAL_BTC_PRICE);
      }

      // Check evaluation passed
      evaluation = await evaluationManager.getEvaluation(trader1.address);
      expect(evaluation.passed).to.be.true;
      expect(evaluation.isActive).to.be.false;

      // Check NFT minted
      expect(await reputationNFT.hasCredential(trader1.address)).to.be.true;
    });
  });

  describe("Failed Evaluation - Drawdown", function () {
    it("Should fail evaluation when drawdown limit exceeded", async function () {
      await usdc.connect(trader1).approve(await evaluationManager.getAddress(), EVALUATION_FEE);
      await evaluationManager.connect(trader1).startEvaluation();

      // Execute multiple losing trades to exceed 5% drawdown
      // Each trade: 4000 USDC position, 4% loss = 160 USDC
      // 4 trades = 640 USDC loss = 6.4% drawdown
      for (let i = 0; i < 4; i++) {
        // Open long position
        await evaluationManager.connect(trader1).executeVirtualTrade(
          "BTC/USD",
          ethers.parseUnits("4000", 6),
          true
        );

        // Price drops by 4%
        const priceDrop = (INITIAL_BTC_PRICE * BigInt(4)) / BigInt(100);
        const lowerPrice = INITIAL_BTC_PRICE - priceDrop;
        await btcOracle.updatePrice(lowerPrice);

        // Close position at loss
        await evaluationManager.connect(trader1).closeVirtualTrade(i + 1);

        // Reset price
        await btcOracle.updatePrice(INITIAL_BTC_PRICE);
        
        // Check if failed after enough losses
        const evaluation = await evaluationManager.getEvaluation(trader1.address);
        if (evaluation.failed) {
          expect(evaluation.isActive).to.be.false;
          expect(await reputationNFT.hasCredential(trader1.address)).to.be.false;
          return; // Test passed
        }
      }

      // If we get here, should have failed by now
      const evaluation = await evaluationManager.getEvaluation(trader1.address);
      expect(evaluation.failed).to.be.true;
    });
  });

  describe("Position Management", function () {
    beforeEach(async function () {
      await usdc.connect(trader1).approve(await evaluationManager.getAddress(), EVALUATION_FEE);
      await evaluationManager.connect(trader1).startEvaluation();
    });

    it("Should track multiple open positions", async function () {
      // Open 3 positions
      await evaluationManager.connect(trader1).executeVirtualTrade("BTC/USD", ethers.parseUnits("100", 6), true);
      await evaluationManager.connect(trader1).executeVirtualTrade("BTC/USD", ethers.parseUnits("100", 6), false);
      await evaluationManager.connect(trader1).executeVirtualTrade("BTC/USD", ethers.parseUnits("100", 6), true);

      const pos1 = await evaluationManager.getPosition(trader1.address, 1);
      const pos2 = await evaluationManager.getPosition(trader1.address, 2);
      const pos3 = await evaluationManager.getPosition(trader1.address, 3);

      expect(pos1.isLong).to.be.true;
      expect(pos2.isLong).to.be.false;
      expect(pos3.isLong).to.be.true;
    });

    it("Should calculate unrealized PnL correctly", async function () {
      await evaluationManager.connect(trader1).executeVirtualTrade("BTC/USD", ethers.parseUnits("100", 6), true);

      // Update price
      await btcOracle.updatePrice(INITIAL_BTC_PRICE + ethers.parseUnits("1000", 8));

      const pnl = await evaluationManager.calculateCurrentPnL(trader1.address, 1);
      expect(pnl).to.be.gt(0); // Should be profitable
    });
  });

  describe("Edge Cases", function () {
    it("Should prevent starting multiple evaluations", async function () {
      await usdc.connect(trader1).approve(await evaluationManager.getAddress(), EVALUATION_FEE * 2n);
      await evaluationManager.connect(trader1).startEvaluation();

      await expect(
        evaluationManager.connect(trader1).startEvaluation()
      ).to.be.revertedWith("EvaluationManager: Already in evaluation");
    });

    it("Should prevent trading without active evaluation", async function () {
      await expect(
        evaluationManager.connect(trader1).executeVirtualTrade("BTC/USD", ethers.parseUnits("100", 6), true)
      ).to.be.revertedWith("EvaluationManager: No active evaluation");
    });

    it("Should prevent closing non-existent position", async function () {
      await usdc.connect(trader1).approve(await evaluationManager.getAddress(), EVALUATION_FEE);
      await evaluationManager.connect(trader1).startEvaluation();

      await expect(
        evaluationManager.connect(trader1).closeVirtualTrade(999)
      ).to.be.revertedWith("EvaluationManager: Position not found");
    });
  });

  describe("Admin Functions", function () {
    it("Should allow admin to emergency stop evaluation", async function () {
      await usdc.connect(trader1).approve(await evaluationManager.getAddress(), EVALUATION_FEE);
      await evaluationManager.connect(trader1).startEvaluation();

      await evaluationManager.connect(owner).emergencyStopEvaluation(trader1.address, "Rule violation");

      const evaluation = await evaluationManager.getEvaluation(trader1.address);
      expect(evaluation.failed).to.be.true;
      expect(evaluation.isActive).to.be.false;
    });

    it("Should allow updating evaluation rules", async function () {
      await evaluationManager.setEvaluationRules(
        ethers.parseUnits("20000", 6), // New virtual balance
        1500, // 15% profit target
        400,  // 4% max drawdown
        10,   // 10 min trades
        60 * 24 * 60 * 60, // 60 days
        ethers.parseUnits("200", 6) // 200 USDC fee
      );

      const rules = await evaluationManager.rules();
      expect(rules.virtualBalance).to.equal(ethers.parseUnits("20000", 6));
    });
  });
});
