import { Address, BigInt } from "@graphprotocol/graph-ts";
import { Vault, VaultEvent } from "../generated/schema";
import {
  LiveTradeExecuted,
  TradeClosed,
  PayoutExecuted,
  DailyLossLimitHit,
  VaultPaused,
} from "../generated/templates/TraderVaultTemplate/TraderVault";

function vaultId(addr: Address): string { return addr.toHexString(); }
function evId(tx: string, logIndex: BigInt): string { return tx + "-" + logIndex.toString(); }

export function handleLiveTradeExecuted(event: LiveTradeExecuted): void {
  let v = Vault.load(vaultId(event.address));
  if (v == null) {
    v = new Vault(vaultId(event.address));
    v.trader = event.transaction.from;
    v.initialCapital = BigInt.zero();
    v.createdAt = event.block.timestamp;
  }
  v.updatedAt = event.block.timestamp;
  v.save();

  let e = new VaultEvent(evId(event.transaction.hash.toHexString(), event.logIndex));
  e.vault = v.id;
  e.kind = "LiveTradeExecuted";
  e.positionId = event.params.positionId;
  e.symbol = event.params.symbol;
  e.size = event.params.size;
  e.isLong = event.params.isLong;
  e.entryPrice = event.params.entryPrice;
  e.timestamp = event.block.timestamp;
  e.txHash = event.transaction.hash;
  e.save();
}

export function handleTradeClosed(event: TradeClosed): void {
  let v = Vault.load(vaultId(event.address));
  if (v != null) {
    v.updatedAt = event.block.timestamp;
    v.save();
  }
  let e = new VaultEvent(evId(event.transaction.hash.toHexString(), event.logIndex));
  e.vault = vaultId(event.address);
  e.kind = "TradeClosed";
  e.positionId = event.params.positionId;
  e.exitPrice = event.params.exitPrice;
  e.pnl = event.params.pnl;
  e.timestamp = event.block.timestamp;
  e.txHash = event.transaction.hash;
  e.save();
}

export function handlePayoutExecuted(event: PayoutExecuted): void {
  let v = Vault.load(vaultId(event.address));
  if (v != null) {
    v.updatedAt = event.block.timestamp;
    v.save();
  }
  let e = new VaultEvent(evId(event.transaction.hash.toHexString(), event.logIndex));
  e.vault = vaultId(event.address);
  e.kind = "PayoutExecuted";
  e.amount = event.params.profit; // store total profit amount
  e.timestamp = event.block.timestamp;
  e.txHash = event.transaction.hash;
  e.save();
}

export function handleDailyLossLimitHit(event: DailyLossLimitHit): void {
  let v = Vault.load(vaultId(event.address));
  if (v != null) {
    v.dailyLoss = event.params.loss;
    v.updatedAt = event.block.timestamp;
    v.save();
  }
  let e = new VaultEvent(evId(event.transaction.hash.toHexString(), event.logIndex));
  e.vault = vaultId(event.address);
  e.kind = "DailyLossLimitHit";
  e.amount = event.params.loss;
  e.timestamp = event.block.timestamp;
  e.txHash = event.transaction.hash;
  e.save();
}

export function handleVaultPaused(event: VaultPaused): void {
  let v = Vault.load(vaultId(event.address));
  if (v != null) {
    v.updatedAt = event.block.timestamp;
    v.save();
  }
  let e = new VaultEvent(evId(event.transaction.hash.toHexString(), event.logIndex));
  e.vault = vaultId(event.address);
  e.kind = "VaultPaused";
  e.timestamp = event.block.timestamp;
  e.txHash = event.transaction.hash;
  e.save();
}
