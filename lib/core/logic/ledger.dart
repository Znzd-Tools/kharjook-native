// Ports of the shared ledger engines:
//   asset-replay-order.ts, calculate-asset-stats.ts, last-trade-price.ts,
//   quantity-epsilon.ts, calculate-wallet-balance.ts, calculate-person-balance.ts,
//   currency-conversion.ts, sort-transactions.ts.

import 'dart:math' as math;

import 'package:collection/collection.dart' show mergeSort;

import '../models.dart';
import '../utils/jalali.dart';
import 'rate_history.dart';

bool isClosedPosition(double remaining, double unitsBefore) =>
    remaining <= math.max(unitsBefore.abs() * 1e-9, 1e-15);

int _createdAtMs(Transaction tx) => DateTime.tryParse(tx.createdAt)?.millisecondsSinceEpoch ?? 0;

/// JS `Number(x)` for nullable doubles: null → 0 (Number(null) === 0).
double jsNum(double? v) => v ?? 0;

bool _pos(double v) => v > 0 && v.isFinite;

int compareTransactionsNewestFirst(Transaction a, Transaction b) {
  final da = parseDateToNumber(a.dateString);
  final db = parseDateToNumber(b.dateString);
  if (da != db) return db - da;
  final ta = _createdAtMs(a);
  final tb = _createdAtMs(b);
  if (ta != tb) return tb - ta;
  return b.id.compareTo(a.id);
}

List<Transaction> sortTransactionsNewestFirst(List<Transaction> list) => [...list]..sort(compareTransactionsNewestFirst);

List<Transaction> orderAssetTxsForReplay(
  List<Transaction> txs,
  bool Function(Transaction) isAcquire,
  double Function(Transaction) qtyOf,
) {
  final sorted = [...txs]
    ..sort((a, b) {
      final da = parseDateToNumber(a.dateString);
      final db = parseDateToNumber(b.dateString);
      if (da != db) return da - db;
      final ca = _createdAtMs(a);
      final cb = _createdAtMs(b);
      if (ca != cb) return ca - cb;
      return a.id.compareTo(b.id);
    });

  final out = <Transaction>[];
  var held = 0.0;
  var i = 0;
  while (i < sorted.length) {
    final day = parseDateToNumber(sorted[i].dateString);
    var j = i;
    while (j < sorted.length && parseDateToNumber(sorted[j].dateString) == day) {
      j += 1;
    }
    final group = sorted.sublist(i, j);
    var sim = held;
    var feasible = true;
    for (final tx in group) {
      final q = qtyOf(tx);
      if (!(q > 0)) continue;
      if (isAcquire(tx)) {
        sim += q;
      } else {
        if (q > sim * (1 + 1e-9) + 1e-15) {
          feasible = false;
          break;
        }
        sim -= q;
      }
    }
    final ordered = feasible ? group : [...group.where(isAcquire), ...group.where((t) => !isAcquire(t))];
    for (final tx in ordered) {
      final q = qtyOf(tx);
      if (!(q > 0)) continue;
      held = isAcquire(tx) ? held + q : held - q;
      out.add(tx);
    }
    for (final tx in ordered) {
      if (!(qtyOf(tx) > 0)) out.add(tx);
    }
    i = j;
  }
  return out;
}

class TradePrice {
  final String date;
  final double priceToman;
  final double priceUsd;
  TradePrice(this.date, this.priceToman, this.priceUsd);
}

bool _txTouchesAsset(Transaction tx, String assetId) =>
    tx.assetId == assetId || tx.sourceAssetId == assetId || tx.targetAssetId == assetId;

TradePrice? latestTradePriceAt(String assetId, String? targetDate, List<Transaction> transactions) {
  String? bestDate;
  String bestCreated = '';
  double bestT = 0, bestU = 0;
  for (final tx in transactions) {
    if (!_txTouchesAsset(tx, assetId)) continue;
    final date = tx.dateString;
    if (date.isEmpty || (targetDate != null && date.compareTo(targetDate) > 0)) continue;
    final priceToman = jsNum(tx.priceToman);
    if (!_pos(priceToman)) continue;
    final rate = jsNum(tx.usdRate);
    var priceUsd = _pos(rate) ? priceToman / rate : double.nan;
    if (!(priceUsd > 0)) {
      final qty = jsNum(tx.amount);
      final usdTotal = jsNum(tx.amountUsdAtTime);
      priceUsd = qty > 0 && usdTotal > 0 ? usdTotal / qty : double.nan;
    }
    if (!_pos(priceUsd)) continue;
    final createdAt = tx.createdAt;
    if (bestDate == null || date.compareTo(bestDate) > 0 || (date == bestDate && createdAt.compareTo(bestCreated) > 0)) {
      bestDate = date;
      bestCreated = createdAt;
      bestT = priceToman;
      bestU = priceUsd;
    }
  }
  return bestDate == null ? null : TradePrice(bestDate, bestT, bestU);
}

double _resolvePriceUsd(Transaction tx, double amount, double priceToman, double usdRate, double? Function(String)? rateAtDate) {
  final txUsdRate = jsNum(tx.usdRate);
  if (_pos(txUsdRate)) return priceToman / txUsdRate;
  final snapshotUsd = jsNum(tx.amountUsdAtTime);
  if (_pos(snapshotUsd) && amount > 0) return snapshotUsd / amount;
  final historical = rateAtDate?.call(tx.dateString);
  if (historical != null && historical > 0) return priceToman / historical;
  return usdRate > 0 ? priceToman / usdRate : 0;
}

AssetStats calculateAssetStats(Asset asset, List<Transaction> transactions, String currencyMode, double usdRate) {
  bool isAcquireType(Transaction tx) =>
      (tx.type == 'BUY' || tx.type == 'INCOME') && (tx.assetId == asset.id || tx.targetAssetId == asset.id);
  bool isDisposeType(Transaction tx) =>
      (tx.type == 'SELL' || tx.type == 'EXPENSE') && (tx.assetId == asset.id || tx.sourceAssetId == asset.id);
  bool isTransferAcquire(Transaction tx) => tx.type == 'TRANSFER' && tx.targetAssetId == asset.id;
  bool isTransferDispose(Transaction tx) => tx.type == 'TRANSFER' && tx.sourceAssetId == asset.id;

  final assetTxs = transactions
      .where((tx) => isAcquireType(tx) || isDisposeType(tx) || isTransferAcquire(tx) || isTransferDispose(tx))
      .toList();

  var totalAmount = 0.0;
  var totalCostToman = 0.0;
  var totalCostUsd = 0.0;
  var realizedProfitToman = 0.0;
  var realizedProfitUsd = 0.0;
  var historicalCostToman = 0.0;
  var historicalCostUsd = 0.0;
  var totalProceedsToman = 0.0;
  var totalProceedsUsd = 0.0;
  String? activeSinceDate;
  var shortUnits = 0.0;
  var shortProceedsToman = 0.0;
  var shortProceedsUsd = 0.0;

  RateHistory? usdHistory;
  double? usdAt(String date) {
    usdHistory ??= usdHistoryFromTransactions(transactions);
    return usdHistory!.at(date);
  }

  bool isAcquireRow(Transaction tx) => isAcquireType(tx) || isTransferAcquire(tx);

  double replayQty(Transaction tx) {
    final double? polyAmount = isAcquireRow(tx)
        ? (tx.targetAssetId == asset.id ? tx.targetAmount : null)
        : (tx.sourceAssetId == asset.id ? tx.sourceAmount : null);
    final amount = jsNum(tx.amount ?? polyAmount);
    final priceToman = tx.priceToman ?? 0;
    if (!amount.isFinite || amount <= 0) return 0;
    if (!priceToman.isFinite || priceToman <= 0) return 0;
    return amount;
  }

  final sortedTxs = orderAssetTxsForReplay(assetTxs, isAcquireRow, replayQty);

  for (final tx in sortedTxs) {
    final isAcquire = isAcquireType(tx) || isTransferAcquire(tx);
    final isDispose = isDisposeType(tx) || isTransferDispose(tx);
    if (!isAcquire && !isDispose) continue;
    final amount = replayQty(tx);
    if (!(amount > 0)) continue;
    final priceToman = jsNum(tx.priceToman);
    final priceUsd = _resolvePriceUsd(tx, amount, priceToman, usdRate, usdAt);

    if (isAcquire) {
      historicalCostToman += amount * priceToman;
      historicalCostUsd += amount * priceUsd;
      var units = amount;
      if (shortUnits > 0) {
        final cover = math.min(units, shortUnits);
        final shortAvgToman = shortProceedsToman / shortUnits;
        final shortAvgUsd = shortProceedsUsd / shortUnits;
        realizedProfitToman += cover * (shortAvgToman - priceToman);
        realizedProfitUsd += cover * (shortAvgUsd - priceUsd);
        final shortBefore = shortUnits;
        shortUnits -= cover;
        shortProceedsToman -= cover * shortAvgToman;
        shortProceedsUsd -= cover * shortAvgUsd;
        if (isClosedPosition(shortUnits, shortBefore)) {
          shortUnits = 0;
          shortProceedsToman = 0;
          shortProceedsUsd = 0;
        }
        units -= cover;
      }
      if (isClosedPosition(units, amount)) continue;
      if (totalAmount <= 0) activeSinceDate = tx.dateString;
      totalAmount += units;
      totalCostToman += units * priceToman;
      totalCostUsd += units * priceUsd;
    } else {
      final unitsBefore = totalAmount;
      if (totalAmount > 0) {
        final avgCostToman = totalCostToman / totalAmount;
        final avgCostUsd = totalCostUsd / totalAmount;
        final drain = math.min(amount, totalAmount);
        totalProceedsToman += drain * priceToman;
        totalProceedsUsd += drain * priceUsd;
        realizedProfitToman += drain * (priceToman - avgCostToman);
        realizedProfitUsd += drain * (priceUsd - avgCostUsd);
        totalCostToman -= drain * avgCostToman;
        totalCostUsd -= drain * avgCostUsd;
        totalAmount -= drain;
      }
      final excess = amount - math.min(amount, math.max(unitsBefore, 0));
      if (excess > math.max(amount * 1e-9, 1e-15)) {
        shortUnits += excess;
        shortProceedsToman += excess * priceToman;
        shortProceedsUsd += excess * priceUsd;
        totalProceedsToman += excess * priceToman;
        totalProceedsUsd += excess * priceUsd;
      }
      if (isClosedPosition(totalAmount, unitsBefore)) {
        totalAmount = 0;
        totalCostToman = 0;
        totalCostUsd = 0;
        activeSinceDate = null;
      }
    }
  }

  final s = AssetStats();
  s.totalAmount = totalAmount;
  s.totalCostToman = totalCostToman;
  s.totalCostUsd = totalCostUsd;
  s.avgBuyPriceToman = totalAmount > 0 ? totalCostToman / totalAmount : 0;
  s.avgBuyPriceUsd = totalAmount > 0 ? totalCostUsd / totalAmount : 0;

  var currentPriceToman = asset.priceToman.isFinite ? asset.priceToman : 0.0;
  var currentPriceUsd = (asset.priceUsd != 0 && asset.priceUsd.isFinite)
      ? asset.priceUsd
      : (usdRate > 0 ? currentPriceToman / usdRate : 0.0);
  var source = currentPriceToman > 0 ? 'live' : 'none';
  String? priceDate;
  if (!(currentPriceToman > 0)) {
    final last = latestTradePriceAt(asset.id, null, assetTxs);
    if (last != null) {
      currentPriceToman = last.priceToman;
      currentPriceUsd = last.priceUsd;
      source = 'trade';
      priceDate = last.date;
    }
  }
  final currentValueToman = totalAmount * currentPriceToman;
  final currentValueUsd = totalAmount * currentPriceUsd;
  final unrealizedProfitToman = currentValueToman - totalCostToman;
  final unrealizedProfitUsd = currentValueUsd - totalCostUsd;
  final profitLossToman = realizedProfitToman + unrealizedProfitToman;
  final profitLossUsd = realizedProfitUsd + unrealizedProfitUsd;
  final profitLossPercent = currencyMode == 'USD'
      ? (historicalCostUsd > 0 ? (profitLossUsd / historicalCostUsd) * 100 : 0.0)
      : (historicalCostToman > 0 ? (profitLossToman / historicalCostToman) * 100 : 0.0);
  final includePnl = asset.includeInProfitLoss;

  s.currentValueToman = currentValueToman;
  s.currentValueUsd = currentValueUsd;
  s.profitLossToman = includePnl ? profitLossToman : 0;
  s.profitLossUsd = includePnl ? profitLossUsd : 0;
  s.profitLossPercent = includePnl ? profitLossPercent : 0;
  s.realizedProfitToman = includePnl ? realizedProfitToman : 0;
  s.realizedProfitUsd = includePnl ? realizedProfitUsd : 0;
  s.unrealizedProfitToman = includePnl ? unrealizedProfitToman : 0;
  s.unrealizedProfitUsd = includePnl ? unrealizedProfitUsd : 0;
  s.investedToman = historicalCostToman;
  s.investedUsd = historicalCostUsd;
  s.proceedsToman = totalProceedsToman;
  s.proceedsUsd = totalProceedsUsd;
  s.activeSinceDate = totalAmount > 0 ? activeSinceDate : null;
  s.currentPriceToman = currentPriceToman;
  s.currentPriceUsd = currentPriceUsd;
  s.currentPriceSource = source;
  s.currentPriceDate = priceDate;
  return s;
}

double assetQuantityFromTransactions(String assetId, List<Transaction> transactions) =>
    calculateAssetStats(Asset.blank(assetId), transactions, 'TOMAN', 1).totalAmount;

// ─── Wallets / persons ─────────────────────────────────────────────────────

class WalletStats {
  final double balance;
  final double incomeTotal;
  final double expenseTotal;
  final double netFlow;
  final List<Transaction> transactions;
  WalletStats(this.balance, this.incomeTotal, this.expenseTotal, this.netFlow, this.transactions);
}

WalletStats calculateWalletStats(Wallet wallet, List<Transaction> transactions) {
  var balance = wallet.initialBalance;
  var income = 0.0, expense = 0.0, net = 0.0;
  final touching = <Transaction>[];
  for (final tx in transactions) {
    final isSource = tx.sourceWalletId == wallet.id;
    final isTarget = tx.targetWalletId == wallet.id;
    if (!isSource && !isTarget) continue;
    touching.add(tx);
    if (isTarget) {
      final v = numOr0(tx.targetAmount);
      balance += v;
      net += v;
      if (tx.type == 'INCOME') income += v;
    }
    if (isSource) {
      final v = numOr0(tx.sourceAmount);
      balance -= v;
      net -= v;
      if (tx.type == 'EXPENSE') expense += v;
    }
  }
  touching.sort(compareTransactionsNewestFirst);
  return WalletStats(balance, income, expense, net, touching);
}

double walletBalanceThroughDate(Wallet wallet, List<Transaction> transactions, String throughDateStr) {
  final limit = parseDateToNumber(throughDateStr);
  var balance = wallet.initialBalance;
  for (final tx in transactions) {
    if (parseDateToNumber(tx.dateString) > limit) continue;
    if (tx.targetWalletId == wallet.id) balance += numOr0(tx.targetAmount);
    if (tx.sourceWalletId == wallet.id) balance -= numOr0(tx.sourceAmount);
  }
  return balance;
}

/// Positive => person owes user (بدهکار); negative => user owes person.
double calculatePersonBalance(Person person, List<Transaction> transactions) {
  var balance = 0.0;
  for (final tx in transactions) {
    if (tx.targetPersonId == person.id) balance += numOr0(tx.targetAmount);
    if (tx.sourcePersonId == person.id) balance -= numOr0(tx.sourceAmount);
  }
  return balance;
}

double tomanPerUnit(String currency, List<CurrencyRate> rates) {
  if (currency == 'IRT') return 1;
  for (final r in rates) {
    if (r.currency == currency && r.tomanPerUnit > 0) return r.tomanPerUnit;
  }
  return 0;
}

double toToman(double amount, String currency, List<CurrencyRate> rates) => amount * tomanPerUnit(currency, rates);

class WalletRate {
  final double rate;
  final String source; // base | saved | history | missing
  WalletRate(this.rate, this.source);
}

WalletRate walletRateNow(String currency, List<CurrencyRate> rates, RateHistories? histories) {
  if (currency == 'IRT') return WalletRate(1, 'base');
  final saved = tomanPerUnit(currency, rates);
  if (saved > 0) return WalletRate(saved, 'saved');
  final last = histories?[currency]?.latest();
  if (last != null && last > 0) return WalletRate(last, 'history');
  return WalletRate(0, 'missing');
}

/// USD rate for a row dated `date` (use-rate-histories.ts `usdRateOn`).
double usdRateOn(RateHistories histories, String date, String todayStr, double currentRate) {
  if (date.isEmpty || date.compareTo(todayStr) >= 0) return currentRate;
  final r = histories['USD']?.at(date);
  return r != null && r > 0 ? r : currentRate;
}

/// Stable sort (JS `Array.prototype.sort` is stable; Dart's `List.sort` is not).
List<T> stableSorted<T>(Iterable<T> items, int Function(T a, T b) compare) {
  final list = items.toList();
  mergeSort(list, compare: compare);
  return list;
}
