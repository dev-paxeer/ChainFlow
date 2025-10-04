import { Address, BigInt } from "@graphprotocol/graph-ts";
import { Vault, Factory, VaultEvent } from "../generated/schema";
import { TraderVaultFactory as FactoryContract, VaultDeployed, VaultFunded, ConfigUpdated } from "../generated/TraderVaultFactory/TraderVaultFactory";
import { TraderVaultTemplate } from "../generated/templates";

function factoryId(addr: Address): string { return addr.toHexString(); }
function vaultId(addr: Address): string { return addr.toHexString(); }
function eventId(tx: string, logIndex: BigInt): string { return tx.concat("-" + logIndex.toString()); }

export function handleVaultDeployed(event: VaultDeployed): void {
  // Factory entity
  let fid = factoryId(event.address);
  let factory = Factory.load(fid);
  if (factory == null) {
    factory = new Factory(fid);
    factory.owner = event.transaction.from;
    factory.totalVaults = 0;
    factory.createdAt = event.block.timestamp;
  }

  // Read default config from contract
  let contract = FactoryContract.bind(event.address);
  let cfg = contract.defaultConfig();
  factory.defaultInitialCapital = cfg.value0;
  factory.defaultMaxPositionSize = cfg.value1;
  factory.defaultMaxDailyLoss = cfg.value2;
  factory.defaultProfitSplitBps = cfg.value3.toI32();
  factory.totalVaults = factory.totalVaults + 1;
  factory.updatedAt = event.block.timestamp;
  factory.save();

  // Vault entity
  let vid = vaultId(event.params.vault);
  let vault = new Vault(vid);
  vault.trader = event.params.trader;
  vault.factory = event.address;
  vault.initialCapital = event.params.initialCapital;
  vault.createdAt = event.block.timestamp;
  vault.updatedAt = event.block.timestamp;
  vault.profitSplitBps = factory.defaultProfitSplitBps;
  vault.save();

  // Dynamic data source for TraderVault
  TraderVaultTemplate.create(event.params.vault);

  // Event
  let ve = new VaultEvent(eventId(event.transaction.hash.toHexString(), event.logIndex));
  ve.vault = vid;
  ve.kind = "VaultDeployed";
  ve.amount = event.params.initialCapital;
  ve.timestamp = event.block.timestamp;
  ve.txHash = event.transaction.hash;
  ve.save();
}

export function handleVaultFunded(event: VaultFunded): void {
  let vid = vaultId(event.params.vault);
  let v = Vault.load(vid);
  if (v != null) {
    v.updatedAt = event.block.timestamp;
    v.save();
  }
  let ve = new VaultEvent(eventId(event.transaction.hash.toHexString(), event.logIndex));
  ve.vault = vid;
  ve.kind = "VaultFunded";
  ve.amount = event.params.amount;
  ve.timestamp = event.block.timestamp;
  ve.txHash = event.transaction.hash;
  ve.save();
}

export function handleConfigUpdated(event: ConfigUpdated): void {
  let fid = factoryId(event.address);
  let f = Factory.load(fid);
  if (f == null) {
    f = new Factory(fid);
    f.owner = event.transaction.from;
    f.totalVaults = 0;
    f.createdAt = event.block.timestamp;
  }
  f.defaultInitialCapital = event.params.initialCapital;
  f.defaultMaxPositionSize = event.params.maxPositionSize;
  f.defaultMaxDailyLoss = event.params.maxDailyLoss;
  f.defaultProfitSplitBps = event.params.profitSplitBps.toI32();
  f.updatedAt = event.block.timestamp;
  f.save();
}
