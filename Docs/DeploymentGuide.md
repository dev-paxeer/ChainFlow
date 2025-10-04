# ChainFlow Deployment Guide

Complete step-by-step guide for deploying the ChainFlow decentralized prop firm platform.

## Prerequisites

### Required Software
- Node.js v18+ and npm
- Hardhat
- Git

### Required Accounts
- Deployer wallet with sufficient ETH for gas
- Admin multisig wallet (recommended for production)
- Price feeder wallets for oracle updates

### Required Tokens
- USDC contract address on target network
- Sufficient USDC for initial treasury funding

## Installation

```bash
# Clone repository
git clone <repository-url>
cd ChainFlow  

# Install dependencies
npm install

# Configure environment
cp .env.example .env
```

## Environment Configuration

Edit `.env` file:

```bash
# Deployer private key (KEEP SECURE!)
PRIVATE_KEY=your_private_key_here

# USDC token address for your network
USDC=0x17070D3E350fe9fDda071538840805eF813D4a37

# Block explorer API keys (for verification)
ETHERSCAN_API_KEY=your_api_key
BASESCAN_API_KEY=your_api_key

# RPC endpoints (if needed)
RPC_URL=https://your-rpc-endpoint
```

## Pre-Deployment Checklist

- [ ] Environment variables configured
- [ ] Deployer wallet funded with gas tokens
- [ ] USDC address verified for network
- [ ] Reviewed default parameters in `scripts/utils/constants.js`
- [ ] Multisig wallet address ready (for production)
- [ ] Backup of private keys secured

## Deployment Steps

### 1. Compile Contracts

```bash
npx hardhat compile
```

Verify no compilation errors.

### 2. Run Tests (Recommended)

```bash
npx hardhat test
```

Ensure all tests pass before deployment.

### 3. Deploy to Local Network (Testing)

```bash
# Terminal 1: Start local node
npx hardhat node

# Terminal 2: Deploy contracts
npx hardhat run scripts/deploy/deploy-all.js --network localhost
```

### 4. Deploy to Production Network

```bash
# Deploy to Paxeer network
npx hardhat run scripts/deploy/deploy-all.js --network paxeer

# Or deploy step-by-step
npx hardhat run scripts/deploy/01-deploy-reputation.js --network paxeer
npx hardhat run scripts/deploy/02-deploy-oracles.js --network paxeer
npx hardhat run scripts/deploy/03-deploy-treasury.js --network paxeer
npx hardhat run scripts/deploy/04-deploy-trading-vault.js --network paxeer
npx hardhat run scripts/deploy/05-deploy-evaluation.js --network paxeer
npx hardhat run scripts/deploy/06-deploy-vault-factory.js --network paxeer
```

### 5. Verify Contracts on Block Explorer

```bash
npx hardhat verify --network paxeer DEPLOYED_CONTRACT_ADDRESS "constructor" "args"
```

Deployment addresses are saved in `deployments/paxeer.json`.

## Post-Deployment Configuration

### 1. Fund Treasury

```bash
# Approve USDC
# Transfer USDC to Treasury
# Call treasury.depositCapital(amount)
```

Recommended: 500,000 - 1,000,000 USDC initial funding.

### 2. Fund Trading Vault

```bash
# Approve USDC
# Call tradingVault.deposit(amount)
```

Recommended: 200,000 - 500,000 USDC for collateral.

### 3. Configure Price Feeders

For each oracle (BTC/USD, ETH/USD, etc.):

```javascript
// Call oracle.setAuthorizedFeeder(feederAddress, true)
```

### 4. Set Up Automated Services

#### Price Feeder Bot
Update oracle prices every 5-10 seconds:

```javascript
setInterval(async () => {
  const btcPrice = await fetchBTCPrice(); // From Chainlink, Binance, etc.
  await btcOracle.updatePrice(btcPrice);
}, 10000);
```

#### Stop-Loss Keeper Bot
Check positions every block:

```javascript
// Monitor all open positions
// Call traderVault.checkStopLoss(positionId) when triggered
```

#### Daily Loss Reset Keeper
Reset daily loss counters at midnight UTC.

### 5. Transfer Ownership to Multisig (Production)

```bash
# For each contract with Ownable
await contract.transferOwnership(MULTISIG_ADDRESS);
```

**Critical**: Verify multisig can execute before transferring.

## Deployment Verification Checklist

After deployment, verify:

- [ ] All contracts deployed successfully
- [ ] Contract addresses saved to deployments file
- [ ] Contracts verified on block explorer
- [ ] ReputationNFT: EvaluationManager has MINTER_ROLE
- [ ] Treasury: Has initial USDC balance
- [ ] TradingVault: Has collateral, exposure limits set
- [ ] VaultFactory: Authorized in Treasury
- [ ] Oracles: Registered in OracleRegistry
- [ ] Oracles: Price feeders authorized
- [ ] All access controls configured correctly
- [ ] Pause mechanisms tested
- [ ] Emergency procedures documented

## Default Configuration

### Evaluation Rules
- Virtual Balance: 10,000 USDC
- Profit Target: 10% (1,000 USDC)
- Max Drawdown: 5%
- Minimum Trades: 5
- Evaluation Period: 30 days
- Evaluation Fee: 100 USDC

### Vault Configuration
- Initial Capital: 100,000 USDC per trader
- Max Position Size: 10,000 USDC
- Max Daily Loss: 2,000 USDC
- Profit Split: 80% trader / 20% firm

### Risk Parameters
- Trading Vault Max Exposure: 80% of collateral
- Min Collateral Ratio: 120%
- Oracle Max Deviation: 5%
- Oracle Heartbeat: 60 seconds

## Modifying Configuration

Edit `scripts/utils/constants.js` before deployment:

```javascript
module.exports = {
  EVALUATION: {
    VIRTUAL_BALANCE: ethers.parseUnits("10000", 6),
    PROFIT_TARGET_BPS: 1000, // 10%
    // ... modify as needed
  },
  // ...
};
```

## Monitoring & Maintenance

### Monitor These Metrics
- Total treasury balance
- Trading vault exposure vs. limits
- Oracle price update frequency
- Number of active evaluations
- Number of funded traders
- Total profit distributed

### Regular Maintenance
- Review and adjust risk parameters monthly
- Update oracle price sources if needed
- Monitor gas costs and optimize
- Review trader performance data
- Audit vault health scores

## Emergency Procedures

### Pause Trading
```javascript
await tradingVault.pauseTrading("Emergency pause reason");
```

### Pause Evaluations
```javascript
await evaluationManager.pause();
```

### Emergency Withdrawal (Last Resort)
```javascript
await tradingVault.emergencyWithdraw(SAFE_ADDRESS, amount);
```

### Revoke Compromised Credential
```javascript
await reputationNFT.revokeCredential(traderAddress, "Reason");
```

## Upgrade Path

Contracts are **not upgradeable** by design for security. To upgrade:

1. Deploy new contract versions
2. Migrate state if possible
3. Update factory to deploy new vault versions
4. Maintain old contracts for existing users

## Support & Resources

- Documentation: [Link to full docs]
- Discord: [Community support]
- Email: support@chainprop.io
- Bug Bounty: [Link to program]

## Security Considerations

### Before Going Live
- [ ] Complete security audit by reputable firm
- [ ] Conduct bug bounty program
- [ ] Test with limited capital first
- [ ] Have incident response plan ready
- [ ] Insurance/coverage considered
- [ ] Legal compliance verified

### Ongoing Security
- Monitor for unusual activity
- Regular contract audits
- Keep dependencies updated
- Maintain secure key management
- Run automated security scans

## Troubleshooting

### Common Issues

**"Insufficient balance" errors**
- Ensure treasury and trading vault are funded
- Check USDC approvals are in place

**"Price is stale" errors**
- Verify price feeders are running
- Check oracle heartbeat settings

**"No valid credential" errors**
- Ensure trader completed evaluation
- Check NFT was minted successfully

**Gas estimation failures**
- Increase gas limit in hardhat.config.js
- Check for reverts in transaction simulation

## Cost Estimates

### Deployment Costs (Estimated)
- All contracts: ~0.5 - 1.5 ETH in gas (varies by network)
- Paxeer network: Lower gas costs

### Ongoing Costs
- Oracle updates: ~$100-500/month
- Keeper bots: ~$50-200/month
- Infrastructure: ~$100-300/month

## Next Steps After Deployment

1. ✅ Contracts deployed and verified
2. ✅ System funded and configured
3. ⏭️ Launch marketing campaign
4. ⏭️ Onboard beta testers
5. ⏭️ Monitor first evaluations
6. ⏭️ Collect feedback and iterate
7. ⏭️ Scale gradually

---

**Remember**: Start small, test thoroughly, scale gradually. The security of user funds is paramount.
