import { Address, BigInt } from "@graphprotocol/graph-ts";
import { Oracle, PriceTick } from "../generated/schema";
import {
  PriceUpdated,
  FeederAuthorized,
  MaxDeviationUpdated,
  HeartbeatUpdated,
  PricesFrozen,
  PriceOracle as OracleContract,
} from "../generated/PriceOracleETH/PriceOracle";

function oracleId(addr: Address): string { return addr.toHexString(); }
function tickId(tx: string, logIndex: BigInt): string { return tx.concat("-" + logIndex.toString()); }

function ensureOracle(addr: Address): Oracle {
  let id = oracleId(addr);
  let o = Oracle.load(id);
  if (o == null) {
    o = new Oracle(id);
    let c = OracleContract.bind(addr);
    let sym = c.symbol();
    o.symbol = sym;
  }
  return o as Oracle;
}

export function handlePriceUpdated(event: PriceUpdated): void {
  let o = ensureOracle(event.address);
  o.latestPrice = event.params.price;
  o.latestTimestamp = event.params.timestamp;
  o.latestRoundId = event.params.roundId;
  o.updatedAt = event.block.timestamp;
  o.save();

  let t = new PriceTick(tickId(event.transaction.hash.toHexString(), event.logIndex));
  t.oracle = oracleId(event.address);
  t.roundId = event.params.roundId;
  t.price = event.params.price;
  t.timestamp = event.params.timestamp;
  t.feeder = event.params.feeder;
  t.txHash = event.transaction.hash;
  t.save();
}

export function handleFeederAuthorized(event: FeederAuthorized): void {
  let o = ensureOracle(event.address);
  o.updatedAt = event.block.timestamp;
  o.save();
}

export function handleMaxDeviationUpdated(event: MaxDeviationUpdated): void {
  let o = ensureOracle(event.address);
  o.maxDeviationBps = event.params.newDeviation.toI32();
  o.updatedAt = event.block.timestamp;
  o.save();
}

export function handleHeartbeatUpdated(event: HeartbeatUpdated): void {
  let o = ensureOracle(event.address);
  o.heartbeatSec = event.params.newTimeout.toI32();
  o.updatedAt = event.block.timestamp;
  o.save();
}

export function handlePricesFrozen(event: PricesFrozen): void {
  let o = ensureOracle(event.address);
  o.updatedAt = event.block.timestamp;
  o.save();
}
