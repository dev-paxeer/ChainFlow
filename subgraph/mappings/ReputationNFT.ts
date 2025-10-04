import { Address, BigInt } from "@graphprotocol/graph-ts";
import { ReputationCredential, Trader } from "../generated/schema";
import {
  CredentialMinted,
  CredentialRevoked,
  BaseURIUpdated,
  ReputationNFT as RepContract,
} from "../generated/ReputationNFT/ReputationNFT";

function credId(tokenId: BigInt): string { return tokenId.toString(); }
function traderId(addr: Address): string { return addr.toHexString(); }

export function handleCredentialMinted(event: CredentialMinted): void {
  const id = credId(event.params.tokenId);
  const c = new ReputationCredential(id);
  c.trader = event.params.trader;
  c.tokenId = event.params.tokenId;
  c.evaluationId = event.params.evaluationId;
  c.profitAchieved = event.params.profitAchieved;
  c.mintedAt = event.block.timestamp;
  c.isValid = true;

  // Enrich with on-chain metadata
  const rep = RepContract.bind(event.address);
  const meta = rep.getMetadata(event.params.tokenId);
  c.finalBalance = meta.finalBalance;
  c.maxDrawdown = meta.maxDrawdown;
  c.totalTrades = meta.totalTrades;
  c.winRateBps = meta.winRate.toI32();
  c.save();

  let t = Trader.load(traderId(event.params.trader));
  if (t == null) t = new Trader(traderId(event.params.trader));
  t.hasCredential = true;
  t.credentialTokenId = event.params.tokenId;
  t.updatedAt = event.block.timestamp;
  t.save();
}

export function handleCredentialRevoked(event: CredentialRevoked): void {
  const id = credId(event.params.tokenId);
  const c = ReputationCredential.load(id);
  if (c != null) {
    c.isValid = false;
    c.revokedAt = event.block.timestamp;
    c.save();
  }
  let t = Trader.load(traderId(event.params.trader));
  if (t != null) {
    t.hasCredential = false;
    t.updatedAt = event.block.timestamp;
    t.save();
  }
}

export function handleBaseURIUpdated(_event: BaseURIUpdated): void {
  // Optionally store baseURI in a Config entity if needed
}
