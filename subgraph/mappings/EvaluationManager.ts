import { Address, BigInt } from "@graphprotocol/graph-ts";
import { Evaluation, VirtualTrade, Trader } from "../generated/schema";
import {
  EvaluationStarted,
  VirtualTradeExecuted,
  VirtualTradeClosed,
  EvaluationPassed,
  EvaluationFailed,
  RulesUpdated,
} from "../generated/EvaluationManager/EvaluationManager";

function evalId(trader: Address): string { return trader.toHexString(); }
function vtId(trader: Address, positionId: BigInt): string {
  return trader.toHexString() + "-" + positionId.toString();
}

export function handleEvaluationStarted(event: EvaluationStarted): void {
  let traderId = event.params.trader;
  let e = new Evaluation(evalId(traderId));
  e.trader = traderId;
  e.evaluationId = event.params.evaluationId;
  e.startTime = event.params.timestamp;
  e.isActive = true;
  e.passed = false;
  e.failed = false;
  e.virtualBalance = event.params.virtualBalance;
  e.highWaterMark = event.params.virtualBalance;
  e.currentDrawdownBps = 0;
  e.tradeCount = 0;
  e.save();

  let t = Trader.load(traderId.toHexString());
  if (t == null) t = new Trader(traderId.toHexString());
  t.currentEvaluationId = event.params.evaluationId;
  t.updatedAt = event.block.timestamp;
  t.save();
}

export function handleVirtualTradeExecuted(event: VirtualTradeExecuted): void {
  let id = vtId(event.params.trader, event.params.positionId);
  let vt = new VirtualTrade(id);
  vt.trader = event.params.trader;
  vt.evaluation = evalId(event.params.trader);
  vt.positionId = event.params.positionId;
  vt.symbol = event.params.symbol;
  vt.size = event.params.size;
  vt.isLong = event.params.isLong;
  vt.entryPrice = event.params.entryPrice;
  vt.openTime = event.block.timestamp;
  vt.txOpen = event.transaction.hash;
  vt.save();
}

export function handleVirtualTradeClosed(event: VirtualTradeClosed): void {
  let id = vtId(event.params.trader, event.params.positionId);
  let vt = VirtualTrade.load(id);
  if (vt == null) return;
  vt.exitPrice = event.params.exitPrice;
  vt.pnl = event.params.pnl;
  vt.closeTime = event.block.timestamp;
  vt.txClose = event.transaction.hash;
  vt.save();

  // bump trade count and virtual balance on evaluation
  let e = Evaluation.load(evalId(event.params.trader));
  if (e != null) {
    e.tradeCount = e.tradeCount + 1;
    e.virtualBalance = event.params.newBalance;
    e.save();
  }
}

export function handleEvaluationPassed(event: EvaluationPassed): void {
  let e = Evaluation.load(evalId(event.params.trader));
  if (e == null) return;
  e.isActive = false;
  e.passed = true;
  e.failed = false;
  e.finalBalance = event.params.finalBalance;
  e.save();
}

export function handleEvaluationFailed(event: EvaluationFailed): void {
  let e = Evaluation.load(evalId(event.params.trader));
  if (e == null) return;
  e.isActive = false;
  e.passed = false;
  e.failed = true;
  e.finalBalance = event.params.finalBalance;
  e.save();
}

export function handleRulesUpdated(_event: RulesUpdated): void {
  // Optionally index global config changes in a separate entity
}
