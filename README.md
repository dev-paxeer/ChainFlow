# Decentralized Prop Firm Platform - Complete Implementation Blueprint

## Project Overview
A fully on-chain proprietary trading firm platform with synthetic asset trading, automated evaluation, reputation-based access control, and instant profit distribution.

---

## Project Structure

```
chaintrack-propfirm/
├── contracts/
│   ├── core/
│   │   ├── EvaluationManager.sol
│   │   ├── TraderVault.sol
│   │   ├── TraderVaultFactory.sol
│   │   └── ProfitSplitter.sol
│   ├── synthetics/
│   │   ├── TradingVault.sol
│   │   ├── PriceOracle.sol
│   │   ├── OracleRegistry.sol
│   │   └── SyntheticsAMM.sol
│   ├── reputation/
│   │   └── ReputationNFT.sol
│   ├── governance/
│   │   └── TreasuryManager.sol
│   └── libraries/
│       ├── Math.sol
│       ├── SafetyChecks.sol
│       └── PositionManager.sol
├── scripts/
│   ├── deploy/
│   │   ├── 01-deploy-reputation.js
│   │   ├── 02-deploy-oracles.js
│   │   ├── 03-deploy-synthetics.js
│   │   ├── 04-deploy-evaluation.js
│   │   ├── 05-deploy-vault-factory.js
│   │   └── 06-verify-contracts.js
│   └── utils/
│       ├── helpers.js
│       └── constants.js
├── test/
│   ├── unit/
│   ├── integration/
│   └── scenarios/
├── hardhat.config.js
├── package.json
└── README.md
```

---

## Smart Contract Specifications

### 1. **ReputationNFT.sol** (Soulbound Token)

**Purpose:** Non-transferable credential proving trader passed evaluation

**Key Features:**
- ERC-721 compliant but blocks all transfers
- Stores trader's evaluation performance metadata
- Only mintable by EvaluationManager contract

**Safety Mechanisms:**
```solidity
// Core safety features to implement:
- Non-transferable (override transfer functions to revert)
- Single mint per evaluation pass
- Immutable metadata once minted
- Emergency pause functionality
- Role-based access control (only EvaluationManager can mint)
```

**Functions Checklist:**
- [ ] `mint(address trader, uint256 evaluationId, bytes metadata)` - Only callable by EvaluationManager
- [ ] `tokenURI(uint256 tokenId)` - Returns evaluation performance data
- [ ] `hasCredential(address trader)` - Quick check if wallet holds NFT
- [ ] `_beforeTokenTransfer()` - Override to block transfers
- [ ] Emergency pause/unpause by admin

**Deployment Checklist:**
- [ ] Deploy with admin multisig address
- [ ] Set EvaluationManager address (can be updated before final lock)
- [ ] Verify base URI is set correctly
- [ ] Test minting permissions
- [ ] Test transfer blocking works
- [ ] Lock contract configuration after testing

---

### 2. **PriceOracle.sol** (Per-Asset Oracle)

**Purpose:** Store and serve price data for specific synthetic asset

**Key Features:**
- High-frequency price updates from authorized feeders
- TWAP calculation for manipulation resistance
- Stale price detection and circuit breakers

**Safety Mechanisms:**
```solidity
// Critical safety features:
- Price deviation limits (reject >X% moves in single update)
- Heartbeat timeout (reject stale prices >Y seconds old)
- Multiple authorized price feeders with consensus
- Emergency price freeze by admin
- Historical price storage for TWAP calculation
```

**State Variables:**
```solidity
struct PriceData {
    uint256 price;          // Latest price (scaled by 1e8)
    uint256 timestamp;      // Last update time
    uint256 roundId;        // Incremental update counter
}

mapping(address => bool) public authorizedFeeders;
PriceData public latestPrice;
PriceData[] public priceHistory; // For TWAP
uint256 public maxPriceDeviation; // e.g., 5% = 500 (basis points)
uint256 public heartbeatTimeout; // e.g., 60 seconds
```

**Functions Checklist:**
- [ ] `updatePrice(uint256 newPrice)` - Only authorized feeders
- [ ] `getLatestPrice()` - Returns price with staleness check
- [ ] `getTWAP(uint256 period)` - Calculate time-weighted average
- [ ] `addFeeder(address feeder)` - Admin only
- [ ] `removeFeeder(address feeder)` - Admin only
- [ ] `setMaxDeviation(uint256 bps)` - Admin only
- [ ] `freezePrices()` - Emergency pause
- [ ] Internal `_validatePrice()` - Check deviation and staleness

**Deployment Checklist:**
- [ ] Deploy one contract per asset (BTC/USD, ETH/USD, EUR/USD, etc.)
- [ ] Set initial price and timestamp
- [ ] Authorize price feeder wallet(s)
- [ ] Configure max deviation (start conservative, e.g., 3%)
- [ ] Set heartbeat timeout (e.g., 30 seconds)
- [ ] Test price updates and rejections
- [ ] Register in OracleRegistry

---

### 3. **OracleRegistry.sol** (Oracle Management)

**Purpose:** Central registry for all price oracles

**Key Features:**
- Map asset symbols to oracle addresses
- Validate oracle health before queries
- Emergency oracle replacement

**Functions Checklist:**
- [ ] `registerOracle(string symbol, address oracle)` - Admin only
- [ ] `getOracle(string symbol)` - Returns oracle address
- [ ] `validateOracle(address oracle)` - Health check
- [ ] `replaceOracle(string symbol, address newOracle)` - Emergency function

**Deployment Checklist:**
- [ ] Deploy registry first
- [ ] Register all deployed oracles
- [ ] Set in EvaluationManager and TradingVault
- [ ] Test symbol lookups

---

### 4. **TradingVault.sol** (Collateral Pool)

**Purpose:** Hold firm's capital and manage collateral for all synthetic positions

**Key Features:**
- Accepts USDC deposits from treasury
- Tracks total collateral and exposure
- Manages risk limits per trader

**Safety Mechanisms:**
```solidity
// Critical risk management:
- Total exposure cap (max % of vault can be at risk)
- Per-trader exposure limits
- Circuit breakers on vault depletion
- Emergency withdrawal by admin only
- Collateralization ratio enforcement (>120%)
```

**State Variables:**
```solidity
IERC20 public collateralToken; // USDC
uint256 public totalCollateral;
uint256 public totalExposure;
uint256 public maxExposureRatio; // e.g., 80% = 8000 bps
mapping(address => uint256) public traderExposure;
uint256 public minCollateralRatio; // e.g., 120% = 12000 bps
```

**Functions Checklist:**
- [ ] `deposit(uint256 amount)` - Treasury only
- [ ] `withdraw(uint256 amount)` - Admin only (emergency)
- [ ] `allocateCollateral(address trader, uint256 amount)` - Internal
- [ ] `releaseCollateral(address trader, uint256 amount)` - Internal
- [ ] `checkExposure()` - View function for risk metrics
- [ ] `setMaxExposure(uint256 ratio)` - Admin only
- [ ] `pauseTrading()` - Emergency function

**Deployment Checklist:**
- [ ] Deploy with USDC token address
- [ ] Set treasury as initial depositor
- [ ] Configure exposure limits (start conservative)
- [ ] Set collateral ratio requirements
- [ ] Initial deposit from treasury
- [ ] Test allocation/release mechanics

---

### 5. **EvaluationManager.sol** (Challenge Phase)

**Purpose:** Manage trader evaluations with virtual trading

**Key Features:**
- Virtual balance simulation
- Rule enforcement (profit targets, drawdown limits)
- On-chain position tracking
- Automated NFT minting on success

**Safety Mechanisms:**
```solidity
// Evaluation integrity protection:
- Immutable rules once evaluation starts
- Anti-gaming: Minimum trade count, time requirements
- Maximum evaluation duration timeout
- Strict drawdown calculation (trailing high-water mark)
- Reentrancy guards on all state-changing functions
```

**State Variables:**
```solidity
struct EvaluationRules {
    uint256 virtualBalance;     // Starting balance (e.g., 10000 USDC)
    uint256 profitTarget;       // Required profit (e.g., 1000 = 10%)
    uint256 maxDrawdown;        // Max loss from HWM (e.g., 500 = 5%)
    uint256 minTrades;          // Min trades to qualify (anti-gaming)
    uint256 evaluationPeriod;   // Max time allowed (e.g., 30 days)
}

struct Evaluation {
    address trader;
    uint256 startTime;
    uint256 virtualBalance;
    uint256 highWaterMark;      // Peak balance achieved
    uint256 currentDrawdown;
    uint256 tradeCount;
    bool isActive;
    bool passed;
    bool failed;
}

struct VirtualPosition {
    uint256 positionId;
    address oracle;             // Which asset
    uint256 entryPrice;
    uint256 size;               // In base units
    bool isLong;
    uint256 collateral;         // Virtual collateral locked
    uint256 openTime;
}

mapping(address => Evaluation) public evaluations;
mapping(address => mapping(uint256 => VirtualPosition)) public positions;
mapping(address => uint256) public positionCounter;
```

**Functions Checklist:**

**Setup & Registration:**
- [ ] `startEvaluation()` - Pay fee, initialize evaluation
- [ ] `setEvaluationRules()` - Admin configures global rules
- [ ] `payEvaluationFee()` - Accept entry fee (USDC)

**Virtual Trading:**
- [ ] `executeVirtualTrade(string asset, uint256 size, bool isLong)` - Open position
  - [ ] Validate evaluation is active
  - [ ] Fetch price from oracle
  - [ ] Calculate required margin
  - [ ] Check sufficient virtual balance
  - [ ] Create position struct
  - [ ] Emit TradeExecuted event
  
- [ ] `closeVirtualTrade(uint256 positionId)` - Close position
  - [ ] Validate position exists and belongs to trader
  - [ ] Fetch current price from oracle
  - [ ] Calculate PnL
  - [ ] Update virtual balance
  - [ ] Update high water mark if new peak
  - [ ] Calculate new drawdown from HWM
  - [ ] Check if drawdown limit violated → fail evaluation
  - [ ] Increment trade counter
  - [ ] Delete position
  - [ ] Emit TradeClosed event

**Evaluation Status:**
- [ ] `checkEvaluationStatus()` - Internal function called after each trade
  - [ ] Check if profit target reached → pass evaluation
  - [ ] Check if drawdown exceeded → fail evaluation
  - [ ] Check if time expired → fail evaluation
  - [ ] If passed: mint ReputationNFT via `_mintCredential()`
  
- [ ] `_mintCredential(address trader)` - Internal
  - [ ] Call ReputationNFT.mint()
  - [ ] Store evaluation metadata
  - [ ] Mark evaluation as passed
  - [ ] Emit EvaluationPassed event

**View Functions:**
- [ ] `getEvaluation(address trader)` - Return full evaluation state
- [ ] `getPosition(address trader, uint256 positionId)` - Return position details
- [ ] `calculateCurrentPnL(address trader, uint256 positionId)` - Unrealized PnL
- [ ] `getOpenPositions(address trader)` - List all open positions

**Admin Functions:**
- [ ] `updateRules()` - Modify global evaluation parameters
- [ ] `emergencyStopEvaluation(address trader)` - Admin intervention
- [ ] `pauseEvaluations()` - Global pause

**Deployment Checklist:**
- [ ] Deploy with OracleRegistry address
- [ ] Deploy with ReputationNFT address
- [ ] Set evaluation fee (e.g., 100 USDC)
- [ ] Configure default rules (profit target, drawdown, min trades)
- [ ] Grant minting permission on ReputationNFT contract
- [ ] Test full evaluation lifecycle
- [ ] Test drawdown calculation accuracy
- [ ] Test edge cases (exact profit target, exact drawdown limit)

---

### 6. **TraderVault.sol** (Individual Funded Trader Contract)

**Purpose:** Isolated vault for each funded trader with real capital

**Key Features:**
- One vault per trader (deployed by factory)
- Holds real USDC from firm
- Executes live trades against TradingVault
- Enforces real-time risk limits
- Automated profit splitting

**Safety Mechanisms:**
```solidity
// Multi-layer protection:
- Owner-only trade execution (trader's wallet)
- Max position size limits
- Max daily loss limits (circuit breaker)
- Mandatory stop-loss on all positions
- Leverage caps
- Cooldown periods between trades (prevent spam)
- Emergency liquidation by admin
- Reentrancy protection
```

**State Variables:**
```solidity
address public owner;              // Trader's wallet
address public treasury;           // Firm's address
uint256 public initialCapital;     // Starting balance
uint256 public currentBalance;     // Current USDC balance
uint256 public highWaterMark;      // For profit calculations
uint256 public totalProfitWithdrawn;

struct LivePosition {
    uint256 positionId;
    address oracle;
    uint256 entryPrice;
    uint256 size;
    bool isLong;
    uint256 collateralLocked;  // Real USDC
    uint256 stopLoss;          // Mandatory
    uint256 takeProfit;        // Optional
    uint256 openTime;
}

mapping(uint256 => LivePosition) public positions;
uint256 public positionCounter;

// Risk limits (set by factory on deployment)
uint256 public maxPositionSize;    // Max single position
uint256 public maxDailyLoss;       // Circuit breaker
uint256 public currentDailyLoss;   // Resets every 24h
uint256 public lastResetTime;      // For daily loss tracking
uint256 public profitSplitBps;     // e.g., 8000 = 80% to trader
```

**Functions Checklist:**

**Trading Functions:**
- [ ] `executeLiveTrade(string asset, uint256 size, bool isLong, uint256 stopLoss, uint256 takeProfit)` - Owner only
  - [ ] Check owner has ReputationNFT
  - [ ] Validate not paused
  - [ ] Check daily loss limit not exceeded
  - [ ] Validate position size within limits
  - [ ] Fetch current price from oracle
  - [ ] Calculate required collateral
  - [ ] Check sufficient vault balance
  - [ ] Transfer collateral to TradingVault
  - [ ] Create position struct
  - [ ] Emit LiveTradeExecuted event

- [ ] `closeLiveTrade(uint256 positionId)` - Owner only
  - [ ] Validate position exists
  - [ ] Fetch current price
  - [ ] Calculate realized PnL
  - [ ] Release collateral from TradingVault
  - [ ] Update vault balance (add/subtract PnL)
  - [ ] If loss: update daily loss counter
  - [ ] If daily loss limit hit: pause vault trading
  - [ ] Update high water mark if profit
  - [ ] Delete position
  - [ ] Emit TradeClosed event

- [ ] `checkStopLoss(uint256 positionId)` - Anyone can call (keeper function)
  - [ ] Fetch current price
  - [ ] Check if stop loss triggered
  - [ ] If yes: auto-close position via `_forceLiquidate()`

**Profit Management:**
- [ ] `requestPayout()` - Owner only
  - [ ] Calculate available profit (currentBalance - highWaterMark)
  - [ ] Require profit > 0
  - [ ] Calculate split (80% trader, 20% treasury)
  - [ ] Transfer trader's share to owner wallet
  - [ ] Transfer firm's share to treasury
  - [ ] Update highWaterMark
  - [ ] Emit PayoutExecuted event

**Risk Management:**
- [ ] `_checkDailyLoss()` - Internal
  - [ ] If 24h passed: reset currentDailyLoss and lastResetTime
  - [ ] If currentDailyLoss >= maxDailyLoss: revert
  
- [ ] `pauseTrading()` - Owner or admin
- [ ] `unpauseTrading()` - Owner only (after reviewing)

**Emergency Functions:**
- [ ] `emergencyWithdraw()` - Admin only (extreme cases)
- [ ] `forceClosePosition(uint256 positionId)` - Admin only

**View Functions:**
- [ ] `getVaultStats()` - Return all key metrics
- [ ] `getOpenPositions()` - List all live positions
- [ ] `getAvailableBalance()` - Balance - locked collateral
- [ ] `calculateUnrealizedPnL()` - Sum of all open position PnLs

**Deployment Checklist:**
- [ ] Cannot deploy directly (only via TraderVaultFactory)
- [ ] Deployed with: owner address, initial capital, risk parameters
- [ ] Test all safety checks (daily loss, position size, etc.)
- [ ] Test profit splitting math
- [ ] Test emergency functions

---

### 7. **TraderVaultFactory.sol** (Vault Deployer)

**Purpose:** Deploy new TraderVault contracts for funded traders

**Key Features:**
- Verify trader has ReputationNFT before deployment
- Deploy unique vault with predefined risk parameters
- Fund vault from treasury
- Track all deployed vaults

**Safety Mechanisms:**
```solidity
// Factory-level protection:
- One vault per trader (prevent duplicate deployments)
- Verify NFT credential before deployment
- Set immutable risk parameters on deployment
- Treasury authorization for funding
- Emergency pause factory
```

**State Variables:**
```solidity
address public reputationNFT;
address public treasury;
address public tradingVault;
address public oracleRegistry;

struct VaultConfig {
    uint256 initialCapital;     // e.g., 100,000 USDC
    uint256 maxPositionSize;    // e.g., 10,000 USDC
    uint256 maxDailyLoss;       // e.g., 2,000 USDC
    uint256 profitSplitBps;     // e.g., 8000 (80/20)
}

VaultConfig public defaultConfig;
mapping(address => address) public traderToVault; // Track deployments
address[] public allVaults;
```

**Functions Checklist:**
- [ ] `deployVault()` - Callable by anyone with ReputationNFT
  - [ ] Verify msg.sender holds ReputationNFT
  - [ ] Verify no existing vault for trader
  - [ ] Deploy new TraderVault with salt (CREATE2 for predictable addresses)
  - [ ] Transfer initialCapital from treasury to new vault
  - [ ] Store mapping trader → vault address
  - [ ] Add to allVaults array
  - [ ] Emit VaultDeployed event

- [ ] `setDefaultConfig(VaultConfig config)` - Admin only
- [ ] `setTreasury(address newTreasury)` - Admin only
- [ ] `getAllVaults()` - View function
- [ ] `getVaultByTrader(address trader)` - View function
- [ ] `pauseFactory()` - Emergency stop new deployments

**Deployment Checklist:**
- [ ] Deploy with ReputationNFT address
- [ ] Deploy with TreasuryManager address
- [ ] Deploy with TradingVault address
- [ ] Set default vault configuration
- [ ] Approve factory to spend USDC from treasury
- [ ] Test vault deployment with valid NFT
- [ ] Test rejection without NFT
- [ ] Test duplicate deployment prevention

---

### 8. **TreasuryManager.sol** (Firm's Capital Management)

**Purpose:** Manage firm's capital pool and allocations

**Functions Checklist:**
- [ ] `depositCapital(uint256 amount)` - Admin only
- [ ] `allocateToVault(address vault, uint256 amount)` - Internal/Factory only
- [ ] `receiveProfit(uint256 amount)` - Called by TraderVaults
- [ ] `withdrawCapital(uint256 amount)` - Admin only
- [ ] `getTreasuryBalance()` - View function
- [ ] `getTotalAllocated()` - View function

**Deployment Checklist:**
- [ ] Deploy with USDC address
- [ ] Set admin multisig
- [ ] Initial capital deposit
- [ ] Approve TraderVaultFactory to spend

---

## Library Contracts

### 9. **Math.sol**
```solidity
// Safe math operations for:
- PnL calculations
- Percentage calculations (profit targets, drawdown)
- Leverage calculations
- TWAP calculations
- Basis point conversions
```

### 10. **SafetyChecks.sol**
```solidity
// Reusable validation functions:
- checkDrawdown(current, hwm, maxDrawdown)
- validatePriceDeviation(oldPrice, newPrice, maxDeviation)
- checkExposureLimit(current, max)
- validatePosition(size, balance, maxSize)
```

### 11. **PositionManager.sol**
```solidity
// Position calculation library:
- calculateRequiredMargin(size, leverage, price)
- calculatePnL(entryPrice, exitPrice, size, isLong)
- calculateLiquidationPrice(entry, size, collateral, isLong)
- checkStopLoss(currentPrice, stopLoss, isLong)
```

---

## Deployment Sequence

### Phase 1: Foundation
```bash
1. Deploy Math.sol library
2. Deploy SafetyChecks.sol library  
3. Deploy PositionManager.sol library
4. Deploy TreasuryManager.sol
5. Deposit initial treasury capital
```

### Phase 2: Reputation System
```bash
6. Deploy ReputationNFT.sol
7. Verify contract on block explorer
8. Test minting permissions
```

### Phase 3: Oracle Infrastructure
```bash
9. Deploy OracleRegistry.sol
10. For each asset:
    - Deploy PriceOracle.sol (BTC, ETH, EUR, etc.)
    - Authorize price feeder wallets
    - Register in OracleRegistry
    - Test price updates
11. Set up automated price feeder service
```

### Phase 4: Trading Infrastructure
```bash
12. Deploy TradingVault.sol
13. Fund TradingVault from treasury
14. Configure exposure limits
15. Test collateral allocation
```

### Phase 5: Evaluation System
```bash
16. Deploy EvaluationManager.sol
17. Link OracleRegistry
18. Link ReputationNFT
19. Grant minting permissions
20. Configure evaluation rules
21. Test full evaluation flow
```

### Phase 6: Funded Trading
```bash
22. Deploy TraderVaultFactory.sol
23. Link all dependencies (NFT, Treasury, Oracles)
24. Configure default vault parameters
25. Approve factory spending from treasury
26. Test vault deployment
27. Test live trading flow
28. Test profit splitting
```

### Phase 7: Verification & Testing
```bash
29. Verify all contracts on block explorer
30. Run full integration test suite
31. Perform security audit
32. Set up monitoring and alerts
33. Configure admin multisig
34. Transfer ownership to multisig
```

---

## Security Checklist

### Smart Contract Security
- [ ] All contracts use OpenZeppelin's latest audited libraries
- [ ] Reentrancy guards on all state-changing functions
- [ ] Access control on admin functions (Ownable/AccessControl)
- [ ] Pause mechanisms for emergencies
- [ ] Input validation on all external functions
- [ ] SafeMath for all arithmetic operations
- [ ] Check-effects-interactions pattern followed
- [ ] No delegatecall to untrusted contracts
- [ ] Events emitted for all state changes
- [ ] Gas limits considered for loops

### Oracle Security
- [ ] Multiple price feeders with consensus mechanism
- [ ] Price deviation limits enforced
- [ ] Stale price detection and rejection
- [ ] Circuit breakers on extreme movements
- [ ] TWAP to prevent manipulation
- [ ] Emergency price freeze capability

### Economic Security
- [ ] Proper collateralization ratios (>120%)
- [ ] Per-trader exposure limits
- [ ] Total vault exposure caps
- [ ] Daily loss limits with circuit breakers
- [ ] Mandatory stop-losses on positions
- [ ] Leverage restrictions
- [ ] Profit distribution tested for edge cases

### Operational Security
- [ ] Admin functions behind multisig (3/5 or 5/9)
- [ ] Timelock on critical parameter changes
- [ ] Emergency pause doesn't brick contracts
- [ ] Upgrade path documented (if using proxies)
- [ ] Off-chain monitoring and alerting
- [ ] Incident response plan documented

---

## Testing Strategy

### Unit Tests (per contract)
```javascript
// Example: EvaluationManager.test.js
- Test evaluation start
- Test virtual trade execution
- Test PnL calculations
- Test drawdown tracking
- Test profit target achievement
- Test evaluation failure scenarios
- Test NFT minting
- Test access control
- Test edge cases (exact targets, rounding errors)
```

### Integration Tests
```javascript
// Test inter-contract communication
- Evaluation → NFT minting
- Factory → Vault deployment  
- Vault → TradingVault interaction
- Vault → Profit splitting
- Oracle → Price feeds → Trade execution
```

### Scenario Tests
```javascript
// Full user journeys
- Complete successful evaluation to payout
- Failed evaluation (drawdown hit)
- Failed evaluation (timeout)
- Multiple traders trading simultaneously
- Circuit breaker triggers
- Emergency pause and recovery
```

---

## Monitoring & Maintenance

### On-Chain Monitoring
- [ ] Total vault exposure vs limits
- [ ] Individual trader risk metrics
- [ ] Oracle price update frequency
- [ ] Failed transaction analysis
- [ ] Gas usage optimization

### Off-Chain Services
- [ ] Automated price feeder (high-frequency updates)
- [ ] Stop-loss keeper bot (check positions every block)
- [ ] Daily loss reset keeper (resets counters at midnight)
- [ ] Emergency alert system (circuit breaker triggers)
- [ ] Performance dashboard (trader leaderboard, vault stats)

---

## Gas Optimization Tips

1. **Use `uint256` over smaller types** (unless packing in structs)
2. **Pack struct variables** by size (group uint8s, uint128s together)
3. **Use mappings over arrays** where possible
4. **Minimize SLOAD operations** (cache storage reads)
5. **Emit events instead of storing data** for historical tracking
6. **Use `calldata` for function parameters** that aren't modified
7. **Batch operations** where possible (e.g., multi-oracle price updates)
8. **Remove dead code** and unused variables

---

## Hardhat Configuration Template

```javascript
// hardhat.config.js
require("@nomicfoundation/hardhat-toolbox");
require("@nomiclabs/hardhat-etherscan");
require("hardhat-gas-reporter");
require("solidity-coverage");
require("dotenv").config();

module.exports = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    hardhat: {
      chainId: 1337,
    },
    yourCustomChain: {
      url: process.env.RPC_URL,
      accounts: [process.env.DEPLOYER_PRIVATE_KEY],
      chainId: YOUR_CHAIN_ID,
    },
  },
  gasReporter: {
    enabled: true,
    currency: "USD",
    coinmarketcap: process.env.COINMARKETCAP_API_KEY,
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
};
```

---

## Final Pre-Launch Checklist

- [ ] All contracts deployed and verified
- [ ] All ownership transferred to multisig
- [ ] Price feeders operational and tested
- [ ] Keeper bots running (stop-loss checks, daily resets)
- [ ] Frontend connected and tested
- [ ] Documentation complete
- [ ] Emergency procedures documented
- [ ] Team trained on emergency response
- [ ] Insurance/bug bounty considered
- [ ] Legal compliance reviewed
- [ ] Community/beta testing completed
- [ ] Marketing materials ready
- [ ] **Launch!** 🚀

---

This blueprint provides a complete, security-focused implementation plan for your decentralized prop firm. Each contract has clear safety mechanisms, all dependencies are mapped, and the deployment sequence ensures a smooth rollout. Follow this checklist methodically, and you'll build a robust, trustless trading platform that revolutionizes the prop firm industry.
