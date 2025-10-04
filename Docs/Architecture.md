# ChainFlow Architecture

## System Overview

ChainFlow is a fully on-chain decentralized proprietary trading firm with three main phases:

1. **Evaluation Phase**: Traders prove skills via virtual trading
2. **Funding Phase**: Successful traders receive real capital
3. **Trading Phase**: Funded traders trade and share profits

## Contract Architecture

### Core Layer

#### ReputationNFT
- Soulbound ERC-721 token
- Non-transferable credential
- Stores evaluation performance data
- One NFT per successful trader

#### EvaluationManager
- Manages virtual trading challenges
- Enforces profit/drawdown rules
- Mints NFTs on success
- Anti-gaming mechanisms

#### TraderVault
- Individual funded account per trader
- Real capital trading
- Risk management (stop-loss, daily limits)
- Automated profit distribution

#### TraderVaultFactory
- Deploys new TraderVaults
- Verifies NFT ownership
- Manages vault configuration
- Tracks all deployments

### Infrastructure Layer

#### TreasuryManager
- Firm's capital pool
- Allocates funds to vaults
- Receives profit share
- Access control

#### TradingVault
- Collateral pool for synthetic positions
- Exposure management
- Risk limits enforcement

### Oracle Layer

#### PriceOracle (per asset)
- High-frequency price feeds
- TWAP calculation
- Staleness detection
- Deviation limits

#### OracleRegistry
- Central oracle management
- Symbol → Oracle mapping
- Health checks

### Library Layer

- **Math**: PnL, drawdown, TWAP calculations
- **SafetyChecks**: Risk validation functions
- **PositionManager**: Position lifecycle

## Data Flow

```
Trader → EvaluationManager → Virtual Trading → Pass/Fail
         ↓ (on pass)
    ReputationNFT Minted
         ↓
    TraderVaultFactory → Deploy TraderVault
         ↓
    TreasuryManager → Fund Vault
         ↓
    Live Trading → Profit → Split (80/20)
```

## Security Model

- Multi-signature admin control
- Role-based access (OpenZeppelin)
- Pausable contracts
- Reentrancy guards
- Circuit breakers
- Mandatory stop-losses
- Daily loss limits

## Key Features

✅ Fully on-chain (no off-chain dependencies)
✅ Automated risk management
✅ Instant profit distribution
✅ Transparent evaluation rules
✅ Isolated trader accounts
✅ Multi-asset support via oracles
