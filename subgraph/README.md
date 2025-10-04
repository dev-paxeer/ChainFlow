# ChainFlow Subgraph

This subgraph indexes ChainFlow contracts on Paxeer Network and exposes a GraphQL API for the frontend and backend.

## Data Sources

- TraderVaultFactory (vault deployments and funding)
- TreasuryManager (capital deposits/withdrawals/allocations/profits)
- TradingVault (collateral, exposure, auth, ratios, pauses)
- OracleRegistry (oracle registration and updates)
- PriceOracle (BTC, ETH) + dynamic template for new oracles
- EvaluationManager (evaluation lifecycle and virtual trades)
- ReputationNFT (credentials)

## Entities

- Factory, Vault, VaultEvent
- Treasury, TreasuryEvent
- TradingVaultEntity, TradingVaultEvent
- Oracle, PriceTick, OracleRegistryEntry
- Evaluation, VirtualTrade, Trader
- ReputationCredential

## Getting Started

```bash
# Install tools
npm -g i @graphprotocol/graph-cli

# Install deps
npm install

# Codegen types
npm run codegen

# Build
npm run build

# Deploy to local Graph Node
npm run create-local
npm run deploy-local
```

Set `network: paxeer` in `subgraph.yaml` and ensure your Graph Node has a matching network definition (chainId 80000).

To deploy remotely, update the `deploy-remote` script or use a self-hosted Graph Node and IPFS.
