const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("ReputationNFT", function () {
  let reputationNFT;
  let owner, minter, trader1, trader2;

  beforeEach(async function () {
    [owner, minter, trader1, trader2] = await ethers.getSigners();

    const ReputationNFT = await ethers.getContractFactory("ReputationNFT");
    reputationNFT = await ReputationNFT.deploy(
      owner.address,
      "https://api.chainprop.io/metadata/"
    );
    await reputationNFT.waitForDeployment();

    // Grant minter role
    const MINTER_ROLE = await reputationNFT.MINTER_ROLE();
    await reputationNFT.grantRole(MINTER_ROLE, minter.address);
  });

  describe("Deployment", function () {
    it("Should set the correct admin", async function () {
      const ADMIN_ROLE = await reputationNFT.ADMIN_ROLE();
      expect(await reputationNFT.hasRole(ADMIN_ROLE, owner.address)).to.be.true;
    });

    it("Should set the correct base URI", async function () {
      // Base URI is private, but we can test tokenURI after minting
    });
  });

  describe("Minting", function () {
    it("Should mint NFT with correct metadata", async function () {
      await reputationNFT.connect(minter).mint(
        trader1.address,
        1, // evaluationId
        ethers.parseUnits("11000", 6), // finalBalance
        ethers.parseUnits("1000", 6),  // profitAchieved
        300, // maxDrawdown (3%)
        10,  // totalTrades
        6500 // winRate (65%)
      );

      expect(await reputationNFT.hasCredential(trader1.address)).to.be.true;
      
      const tokenId = await reputationNFT.getTokenId(trader1.address);
      expect(tokenId).to.equal(1);

      const metadata = await reputationNFT.getMetadata(tokenId);
      expect(metadata.evaluationId).to.equal(1);
      expect(metadata.isValid).to.be.true;
    });

    it("Should prevent duplicate minting", async function () {
      await reputationNFT.connect(minter).mint(
        trader1.address,
        1,
        ethers.parseUnits("11000", 6),
        ethers.parseUnits("1000", 6),
        300,
        10,
        6500
      );

      await expect(
        reputationNFT.connect(minter).mint(
          trader1.address,
          2,
          ethers.parseUnits("12000", 6),
          ethers.parseUnits("2000", 6),
          200,
          15,
          7000
        )
      ).to.be.revertedWith("ReputationNFT: Trader already has credential");
    });

    it("Should only allow minter role to mint", async function () {
      await expect(
        reputationNFT.connect(trader1).mint(
          trader2.address,
          1,
          ethers.parseUnits("11000", 6),
          ethers.parseUnits("1000", 6),
          300,
          10,
          6500
        )
      ).to.be.reverted;
    });
  });

  describe("Soulbound Functionality", function () {
    beforeEach(async function () {
      await reputationNFT.connect(minter).mint(
        trader1.address,
        1,
        ethers.parseUnits("11000", 6),
        ethers.parseUnits("1000", 6),
        300,
        10,
        6500
      );
    });

    it("Should prevent transfers", async function () {
      const tokenId = await reputationNFT.getTokenId(trader1.address);
      
      await expect(
        reputationNFT.connect(trader1).transferFrom(trader1.address, trader2.address, tokenId)
      ).to.be.revertedWith("ReputationNFT: Token is non-transferable");
    });

    it("Should prevent safe transfers", async function () {
      const tokenId = await reputationNFT.getTokenId(trader1.address);
      
      await expect(
        reputationNFT.connect(trader1)["safeTransferFrom(address,address,uint256)"](
          trader1.address,
          trader2.address,
          tokenId
        )
      ).to.be.revertedWith("ReputationNFT: Token is non-transferable");
    });
  });

  describe("Revocation", function () {
    beforeEach(async function () {
      await reputationNFT.connect(minter).mint(
        trader1.address,
        1,
        ethers.parseUnits("11000", 6),
        ethers.parseUnits("1000", 6),
        300,
        10,
        6500
      );
    });

    it("Should allow admin to revoke credential", async function () {
      await reputationNFT.connect(owner).revokeCredential(
        trader1.address,
        "Violation of terms"
      );

      expect(await reputationNFT.hasCredential(trader1.address)).to.be.false;
      expect(await reputationNFT.hasValidCredential(trader1.address)).to.be.false;
    });

    it("Should only allow admin to revoke", async function () {
      await expect(
        reputationNFT.connect(trader2).revokeCredential(trader1.address, "Test")
      ).to.be.reverted;
    });
  });

  describe("Query Functions", function () {
    beforeEach(async function () {
      await reputationNFT.connect(minter).mint(
        trader1.address,
        1,
        ethers.parseUnits("11000", 6),
        ethers.parseUnits("1000", 6),
        300,
        10,
        6500
      );
    });

    it("Should return correct credential status", async function () {
      expect(await reputationNFT.hasValidCredential(trader1.address)).to.be.true;
      expect(await reputationNFT.hasValidCredential(trader2.address)).to.be.false;
    });

    it("Should return correct total supply", async function () {
      expect(await reputationNFT.totalSupply()).to.equal(1);
      
      await reputationNFT.connect(minter).mint(
        trader2.address,
        2,
        ethers.parseUnits("11000", 6),
        ethers.parseUnits("1000", 6),
        300,
        10,
        6500
      );
      
      expect(await reputationNFT.totalSupply()).to.equal(2);
    });
  });

  describe("Pause Functionality", function () {
    it("Should allow admin to pause", async function () {
      await reputationNFT.connect(owner).pause();
      expect(await reputationNFT.paused()).to.be.true;
    });

    it("Should prevent minting when paused", async function () {
      await reputationNFT.connect(owner).pause();
      
      await expect(
        reputationNFT.connect(minter).mint(
          trader1.address,
          1,
          ethers.parseUnits("11000", 6),
          ethers.parseUnits("1000", 6),
          300,
          10,
          6500
        )
      ).to.be.reverted;
    });

    it("Should allow unpausing", async function () {
      await reputationNFT.connect(owner).pause();
      await reputationNFT.connect(owner).unpause();
      expect(await reputationNFT.paused()).to.be.false;
    });
  });
});
