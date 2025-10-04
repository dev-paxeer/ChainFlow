const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Math Library", function () {
  let mathTest;

  before(async function () {
    const TestMath = await ethers.getContractFactory("TestMath");
    mathTest = await TestMath.deploy();
    await mathTest.waitForDeployment();
  });

  describe("calculatePnL", function () {
    it("Should calculate profit for long position", async function () {
      const entryPrice = ethers.parseUnits("50000", 8);
      const exitPrice = ethers.parseUnits("55000", 8);
      const size = ethers.parseUnits("1000000", 6);
      const isLong = true;

      const pnl = await mathTest.calculatePnL(entryPrice, exitPrice, size, isLong);
      expect(pnl).to.be.gt(0);
    });

    it("Should calculate loss for long position", async function () {
      const entryPrice = ethers.parseUnits("50000", 8);
      const exitPrice = ethers.parseUnits("45000", 8);
      const size = ethers.parseUnits("1000000", 6);
      const isLong = true;

      const pnl = await mathTest.calculatePnL(entryPrice, exitPrice, size, isLong);
      expect(pnl).to.be.lt(0);
    });

    it("Should calculate profit for short position", async function () {
      const entryPrice = ethers.parseUnits("50000", 8);
      const exitPrice = ethers.parseUnits("45000", 8);
      const size = ethers.parseUnits("1000000", 6);
      const isLong = false;

      const pnl = await mathTest.calculatePnL(entryPrice, exitPrice, size, isLong);
      expect(pnl).to.be.gt(0);
    });
  });

  describe("calculateDrawdown", function () {
    it("Should calculate drawdown correctly", async function () {
      const currentBalance = ethers.parseUnits("9500", 6);
      const highWaterMark = ethers.parseUnits("10000", 6);

      const drawdown = await mathTest.calculateDrawdown(currentBalance, highWaterMark);
      expect(drawdown).to.equal(500); // 5%
    });

    it("Should return 0 when balance >= HWM", async function () {
      const currentBalance = ethers.parseUnits("10500", 6);
      const highWaterMark = ethers.parseUnits("10000", 6);

      const drawdown = await mathTest.calculateDrawdown(currentBalance, highWaterMark);
      expect(drawdown).to.equal(0);
    });
  });

  describe("applyBasisPoints", function () {
    it("Should apply basis points correctly", async function () {
      const value = ethers.parseUnits("10000", 6);
      const bps = 1000; // 10%

      const result = await mathTest.applyBasisPoints(value, bps);
      expect(result).to.equal(ethers.parseUnits("1000", 6));
    });

    it("Should handle 100% (10000 bps)", async function () {
      const value = ethers.parseUnits("10000", 6);
      const bps = 10000; // 100%

      const result = await mathTest.applyBasisPoints(value, bps);
      expect(result).to.equal(value);
    });
  });

  describe("splitProfit", function () {
    it("Should split profit 80/20", async function () {
      const totalProfit = ethers.parseUnits("1000", 6);
      const traderShareBps = 8000; // 80%

      const [traderAmount, firmAmount] = await mathTest.splitProfit(totalProfit, traderShareBps);
      expect(traderAmount).to.equal(ethers.parseUnits("800", 6));
      expect(firmAmount).to.equal(ethers.parseUnits("200", 6));
    });

    it("Should handle edge case of 100% to trader", async function () {
      const totalProfit = ethers.parseUnits("1000", 6);
      const traderShareBps = 10000; // 100%

      const [traderAmount, firmAmount] = await mathTest.splitProfit(totalProfit, traderShareBps);
      expect(traderAmount).to.equal(totalProfit);
      expect(firmAmount).to.equal(0);
    });
  });
});
