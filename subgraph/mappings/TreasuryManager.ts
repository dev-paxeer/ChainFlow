import { Address, BigInt } from "@graphprotocol/graph-ts";
import { Treasury, TreasuryEvent } from "../generated/schema";
import {
  CapitalAllocated,
  CapitalDeposited,
  CapitalWithdrawn,
  ProfitReceived,
  TreasuryManager as TreasuryContract,
} from "../generated/TreasuryManager/TreasuryManager";

function treasuryId(addr: Address): string { return addr.toHexString(); }
function evId(tx: string, logIndex: BigInt): string { return tx + "-" + logIndex.toString(); }

function syncTreasury(addr: Address, updatedAt: BigInt): Treasury {
  let id = treasuryId(addr);
  let t = Treasury.load(id);
  if (t == null) t = new Treasury(id);
  let c = TreasuryContract.bind(addr);
  t.totalAllocated = c.totalAllocated();
  t.totalProfitCollected = c.totalProfitCollected();
  t.updatedAt = updatedAt;
  t.save();
  return t as Treasury;
}

export function handleCapitalDeposited(event: CapitalDeposited): void {
  syncTreasury(event.address, event.block.timestamp);
  let e = new TreasuryEvent(evId(event.transaction.hash.toHexString(), event.logIndex));
  e.treasury = treasuryId(event.address);
  e.kind = "CapitalDeposited";
  e.amount = event.params.amount;
  e.timestamp = event.block.timestamp;
  e.txHash = event.transaction.hash;
  e.save();
}

export function handleCapitalWithdrawn(event: CapitalWithdrawn): void {
  syncTreasury(event.address, event.block.timestamp);
  let e = new TreasuryEvent(evId(event.transaction.hash.toHexString(), event.logIndex));
  e.treasury = treasuryId(event.address);
  e.kind = "CapitalWithdrawn";
  e.amount = event.params.amount;
  e.timestamp = event.block.timestamp;
  e.txHash = event.transaction.hash;
  e.save();
}

export function handleCapitalAllocated(event: CapitalAllocated): void {
  syncTreasury(event.address, event.block.timestamp);
  let e = new TreasuryEvent(evId(event.transaction.hash.toHexString(), event.logIndex.toI32()));
  e.treasury = treasuryId(event.address);
  e.kind = "CapitalAllocated";
  e.vault = event.params.vault;
  e.amount = event.params.amount;
  e.timestamp = event.block.timestamp;
  e.txHash = event.transaction.hash;
  e.save();
}

export function handleProfitReceived(event: ProfitReceived): void {
  syncTreasury(event.address, event.block.timestamp);
  let e = new TreasuryEvent(evId(event.transaction.hash.toHexString(), event.logIndex.toI32()));
  e.treasury = treasuryId(event.address);
  e.kind = "ProfitReceived";
  e.vault = event.params.vault;
  e.amount = event.params.amount;
  e.timestamp = event.block.timestamp;
  e.txHash = event.transaction.hash;
  e.save();
}
