import { Address, BigInt } from "@graphprotocol/graph-ts";
import { TradingVaultEntity, TradingVaultEvent } from "../generated/schema";
import {
  CollateralDeposited,
  CollateralWithdrawn,
  CollateralAllocated,
  CollateralReleased,
  ExposureUpdated,
  TraderAuthorized,
  ExposureRatioUpdated,
  CollateralRatioUpdated,
  TradingPaused,
  TradingVault as TradingVaultContract,
} from "../generated/TradingVault/TradingVault";

function tvId(addr: Address): string { return addr.toHexString(); }
function evId(tx: string, logIndex: BigInt): string { return tx + "-" + logIndex.toString(); }

function syncTradingVault(addr: Address, ts: BigInt): TradingVaultEntity {
  let id = tvId(addr);
  let t = TradingVaultEntity.load(id);
  if (t == null) t = new TradingVaultEntity(id);
  let c = TradingVaultContract.bind(addr);
  t.totalCollateral = c.totalCollateral();
  t.totalExposure = c.totalExposure();
  t.maxExposureRatio = c.maxExposureRatio().toI32();
  t.minCollateralRatio = c.minCollateralRatio().toI32();
  t.updatedAt = ts;
  t.save();
  return t as TradingVaultEntity;
}

export function handleCollateralDeposited(event: CollateralDeposited): void {
  syncTradingVault(event.address, event.block.timestamp);
  let e = new TradingVaultEvent(evId(event.transaction.hash.toHexString(), event.logIndex));
  e.tradingVault = tvId(event.address);
  e.kind = "CollateralDeposited";
  e.amount = event.params.amount;
  e.timestamp = event.block.timestamp;
  e.txHash = event.transaction.hash;
  e.save();
}

export function handleCollateralWithdrawn(event: CollateralWithdrawn): void {
  syncTradingVault(event.address, event.block.timestamp);
  let e = new TradingVaultEvent(evId(event.transaction.hash.toHexString(), event.logIndex));
  e.tradingVault = tvId(event.address);
  e.kind = "CollateralWithdrawn";
  e.amount = event.params.amount;
  e.timestamp = event.block.timestamp;
  e.txHash = event.transaction.hash;
  e.save();
}

export function handleCollateralAllocated(event: CollateralAllocated): void {
  syncTradingVault(event.address, event.block.timestamp);
  let e = new TradingVaultEvent(evId(event.transaction.hash.toHexString(), event.logIndex));
  e.tradingVault = tvId(event.address);
  e.kind = "CollateralAllocated";
  e.trader = event.params.trader;
  e.amount = event.params.amount;
  e.timestamp = event.block.timestamp;
  e.txHash = event.transaction.hash;
  e.save();
}

export function handleCollateralReleased(event: CollateralReleased): void {
  syncTradingVault(event.address, event.block.timestamp);
  let e = new TradingVaultEvent(evId(event.transaction.hash.toHexString(), event.logIndex));
  e.tradingVault = tvId(event.address);
  e.kind = "CollateralReleased";
  e.trader = event.params.trader;
  e.amount = event.params.amount;
  e.timestamp = event.block.timestamp;
  e.txHash = event.transaction.hash;
  e.save();
}

export function handleExposureUpdated(event: ExposureUpdated): void {
  syncTradingVault(event.address, event.block.timestamp);
  let e = new TradingVaultEvent(evId(event.transaction.hash.toHexString(), event.logIndex));
  e.tradingVault = tvId(event.address);
  e.kind = "ExposureUpdated";
  e.trader = event.params.trader;
  e.oldExposure = event.params.oldExposure;
  e.newExposure = event.params.newExposure;
  e.timestamp = event.block.timestamp;
  e.txHash = event.transaction.hash;
  e.save();
}

export function handleTraderAuthorized(event: TraderAuthorized): void {
  syncTradingVault(event.address, event.block.timestamp);
  let e = new TradingVaultEvent(evId(event.transaction.hash.toHexString(), event.logIndex));
  e.tradingVault = tvId(event.address);
  e.kind = "TraderAuthorized";
  e.trader = event.params.trader;
  e.timestamp = event.block.timestamp;
  e.txHash = event.transaction.hash;
  e.save();
}

export function handleExposureRatioUpdated(event: ExposureRatioUpdated): void {
  syncTradingVault(event.address, event.block.timestamp);
  let e = new TradingVaultEvent(evId(event.transaction.hash.toHexString(), event.logIndex));
  e.tradingVault = tvId(event.address);
  e.kind = "ExposureRatioUpdated";
  e.timestamp = event.block.timestamp;
  e.txHash = event.transaction.hash;
  e.save();
}

export function handleCollateralRatioUpdated(event: CollateralRatioUpdated): void {
  syncTradingVault(event.address, event.block.timestamp);
  let e = new TradingVaultEvent(evId(event.transaction.hash.toHexString(), event.logIndex));
  e.tradingVault = tvId(event.address);
  e.kind = "CollateralRatioUpdated";
  e.timestamp = event.block.timestamp;
  e.txHash = event.transaction.hash;
  e.save();
}

export function handleTradingPaused(event: TradingPaused): void {
  syncTradingVault(event.address, event.block.timestamp);
  let e = new TradingVaultEvent(evId(event.transaction.hash.toHexString(), event.logIndex));
  e.tradingVault = tvId(event.address);
  e.kind = "TradingPaused";
  e.timestamp = event.block.timestamp;
  e.txHash = event.transaction.hash;
  e.save();
}
