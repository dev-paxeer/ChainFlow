import { Address } from "@graphprotocol/graph-ts";
import { OracleRegistryEntry } from "../generated/schema";
import {
  OracleRegistered,
  OracleUpdated,
  OracleRemoved,
} from "../generated/OracleRegistry/OracleRegistry";
import { PriceOracleTemplate } from "../generated/templates";

function entryId(symbol: string): string { return symbol; }

export function handleOracleRegistered(event: OracleRegistered): void {
  let id = entryId(event.params.symbol);
  let e = OracleRegistryEntry.load(id);
  if (e == null) e = new OracleRegistryEntry(id);
  e.symbol = event.params.symbol;
  e.oracle = event.params.oracle;
  e.updatedAt = event.block.timestamp;
  e.save();

  // Start indexing the oracle
  PriceOracleTemplate.create(event.params.oracle);
}

export function handleOracleUpdated(event: OracleUpdated): void {
  let id = entryId(event.params.symbol);
  let e = OracleRegistryEntry.load(id);
  if (e == null) e = new OracleRegistryEntry(id);
  e.symbol = event.params.symbol;
  e.oracle = event.params.newOracle;
  e.updatedAt = event.block.timestamp;
  e.save();

  // Start indexing the new oracle
  PriceOracleTemplate.create(event.params.newOracle);
}

export function handleOracleRemoved(event: OracleRemoved): void {
  let id = entryId(event.params.symbol);
  let e = OracleRegistryEntry.load(id);
  if (e == null) e = new OracleRegistryEntry(id);
  e.symbol = event.params.symbol;
  e.oracle = event.params.oracle;
  e.updatedAt = event.block.timestamp;
  e.save();
}
