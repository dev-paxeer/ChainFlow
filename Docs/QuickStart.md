# ChainFlow - Quick Start Guide

## 🚀 Getting Started in 5 Minutes

### 1. Install Dependencies

```bash
npm install
```

### 2. Compile Contracts

```bash
npx hardhat compile
```

### 3. Run Tests

```bash
npx hardhat test
```

### 4. Deploy Locally (Optional)

```bash
# Terminal 1: Start local node
npx hardhat node

# Terminal 2: Deploy
npx hardhat run scripts/deploy/deploy-all.js --network localhost
```

### 5. Deploy to Paxeer Network

```bash
# Ensure .env is configured with PRIVATE_KEY and USDC address
npx hardhat run scripts/deploy/deploy-all.js --network paxeer
```

## 📋 What Gets Deployed

1. **ReputationNFT** - Soulbound credentials for traders
2. **Oracle System** - Price feeds (BTC/USD, ETH/USD, etc.)
3. **TreasuryManager** - Firm's capital management
4. **TradingVault** - Collateral pool
5. **EvaluationManager** - Virtual trading challenges
6. **TraderVaultFactory** - Funded vault deployer

## 🎯 User Flow

### For Traders:

1. **Pay 100 USDC fee** → Start evaluation
2. **Complete virtual trading** → Achieve 10% profit with max 5% drawdown
3. **Receive NFT credential** → Proof of skill
4. **Deploy funded vault** → Get 100,000 USDC capital
5. **Trade with real money** → Keep 80% of profits

### For Admins:

1. **Deploy contracts** → One-time setup
2. **Fund treasury** → Add USDC capital
3. **Set up price feeders** → Automated oracle updates
4. **Monitor system** → Risk metrics and vault health

## 🔑 Key Features

✅ **100% On-Chain** - No centralized servers
✅ **Automated Evaluation** - Smart contract enforces rules
✅ **Instant Payouts** - 80/20 split executed on-chain
✅ **Risk Management** - Stop-loss, daily limits, circuit breakers
✅ **Transparent** - All activity verifiable on-chain

## 📊 Default Parameters

- Evaluation: 10,000 USDC virtual balance, 10% target, 5% max drawdown
- Funding: 100,000 USDC per trader
- Profit Split: 80% trader / 20% firm
- Max Position: 10,000 USDC
- Daily Loss Limit: 2,000 USDC

## 🛠️ Next Steps

- Review `DEPLOYMENT_GUIDE.md` for detailed deployment
- Check `ARCHITECTURE.md` for system design
- Run tests: `npx hardhat test`
- Customize parameters in `scripts/utils/constants.js`

## 📞 Support

- GitHub Issues: [Report bugs]
- Documentation: [Full docs]
- Community: [Discord/Telegram]
