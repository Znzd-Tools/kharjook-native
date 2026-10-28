// Ports of price-history.ts, asset-period-stats.ts, asset-pnl.ts,
// ytd-unrealized.ts, portfolio-history.ts, year-cashflow.ts.

import 'dart:math' as math;

import '../models.dart';
import '../utils/jalali.dart';
import '../utils/period.dart';
import 'ledger.dart';
import 'rate_history.dart';

class EffectivePrice {
  final double priceToman;
  final double priceUsd;
  final String sourceDate;
  final bool isLive;
  EffectivePrice(this.priceToman, this.priceUsd, this.sourceDate, this.isLive);
}

EffectivePrice? effectivePriceAt(
  Asset asset,
  String targetDate,
  List<DailyPrice> dailyPrices,
  String todayDate, [
  List<Transaction>? transactions,
]) {
  if (targetDate.compareTo(todayDate) >= 0) {
    final t = asset.priceToman;
    final u = asset.priceUsd;
    if (t.isFinite && t > 0 && u.isFinite && u > 0) {
      return EffectivePrice(t, u, todayDate, true);
    }
    if (transactions == null) return null;
  }
  DailyPrice? best;
  for (final p in dailyPrices) {
    if (p.assetId != asset.id) continue;
    if (p.dateString.compareTo(targetDate) > 0) continue;
    if (!(p.priceToman > 0) || !(p.priceUsd > 0)) continue;
    if (best == null || p.dateString.compareTo(best.dateString) > 0) best = p;
  }
  final trade = transactions != null ? latestTradePriceAt(asset.id, targetDate, transactions) : null;
  if (trade != null && (best == null || trade.date.compareTo(best.dateString) > 0)) {
    return EffectivePrice(trade.priceToman, trade.priceUsd, trade.date, false);
  }
  if (best == null) return null;
  return EffectivePrice(best.priceToman, best.priceUsd, best.dateString, false);
}

EffectivePrice? effectiveOpeningPriceAt(
  Asset asset,
  JDate periodStart,
  List<DailyPrice> dailyPrices,
  String todayDate, [
  List<Transaction>? transactions,
]) {
  final dayBefore = formatJalaali(addDays(periodStart, -1));
  return effectivePriceAt(asset, dayBefore, dailyPrices, todayDate, transactions) ??
      effectivePriceAt(asset, formatJalaali(periodStart), dailyPrices, todayDate, transactions);
}

// ─── Period stats ───────────────────────────────────────────────────────────

class SideAggregate {
  double units = 0;
  double totalToman = 0;
  double totalUsd = 0;
  double avgPriceToman = 0;
  double avgPriceUsd = 0;
  int count = 0;
}

class AssetPeriodStats {
  final String assetId;
  final SideAggregate bought = SideAggregate();
  final SideAggregate sold = SideAggregate();
  double realizedToman = 0;
  double realizedUsd = 0;
  double realizedVsCostToman = 0;
  double realizedVsCostUsd = 0;
  double startHoldings = 0;
  double endHoldings = 0;
  double endCostBasisToman = 0;
  double endCostBasisUsd = 0;
  double endAvgCostToman = 0;
  double endAvgCostUsd = 0;
  double currentHoldings = 0;
  double currentCostBasisToman = 0;
  double currentCostBasisUsd = 0;
  double currentAvgCostToman = 0;
  double currentAvgCostUsd = 0;
  double periodUnrealizedToman = 0;
  double periodUnrealizedUsd = 0;
  bool periodUnrealizedAvailable = true;
  double unrealizedToman = 0;
  double unrealizedUsd = 0;
  bool unrealizedAvailable = true;
  double? periodStartPriceToman;
  double? periodStartPriceUsd;
  double? periodEndPriceToman;
  double? periodEndPriceUsd;
  String? periodEndPriceSourceDate;
  bool periodEndPriceIsLive = false;
  bool hadActivity = false;
  bool periodBaselineMissing = false;
  int invalidTradeCount = 0;
  int oversellCount = 0;
  AssetPeriodStats(this.assetId);
}

class _Trade {
  final double amount, priceToman, priceUsd;
  _Trade(this.amount, this.priceToman, this.priceUsd);
}

_Trade? _readTrade(Transaction tx, double usdRateFallback, double? Function(String)? rateAtDate) {
  final polyAmount = (tx.type == 'BUY' || tx.type == 'INCOME') ? tx.targetAmount : tx.sourceAmount;
  final amount = jsNum(tx.amount ?? polyAmount);
  var priceToman = jsNum(tx.priceToman);
  if (!priceToman.isFinite || priceToman <= 0) {
    if (tx.type == 'BUY' || tx.type == 'SELL') {
      final money = jsNum(tx.type == 'BUY' ? tx.sourceAmount : tx.targetAmount);
      if (money.isFinite && money > 0 && amount.isFinite && amount > 0) priceToman = money / amount;
    }
  }
  if (!amount.isFinite || amount <= 0) return null;
  if (!priceToman.isFinite || priceToman <= 0) return null;
  final own = jsNum(tx.usdRate);
  final historical = own > 0 ? null : rateAtDate?.call(tx.dateString);
  final rate = own > 0 ? own : (historical != null && historical > 0 ? historical : usdRateFallback);
  if (!(rate > 0)) return null;
  return _Trade(amount, priceToman, priceToman / rate);
}

bool isAcquireForAsset(Transaction tx, String assetId) {
  if (tx.type == 'BUY') return tx.assetId == assetId || tx.targetAssetId == assetId;
  if (tx.type == 'INCOME') return tx.targetAssetId == assetId || tx.assetId == assetId;
  if (tx.type == 'TRANSFER') return tx.targetAssetId == assetId;
  return false;
}

bool isDisposeForAsset(Transaction tx, String assetId) {
  if (tx.type == 'SELL') return tx.assetId == assetId || tx.sourceAssetId == assetId;
  if (tx.type == 'EXPENSE') return tx.sourceAssetId == assetId || tx.assetId == assetId;
  if (tx.type == 'TRANSFER') return tx.sourceAssetId == assetId;
  return false;
}

AssetPeriodStats calculateAssetPeriodStats(
  Asset asset,
  List<Transaction> transactions,
  Period period,
  double usdRateFallback,
  EffectivePrice? periodEndPrice, [
  EffectivePrice? periodStartPrice,
]) {
  if (!asset.includeInProfitLoss) return AssetPeriodStats(asset.id);
  final assetTxs = transactions.where((tx) => isAcquireForAsset(tx, asset.id) || isDisposeForAsset(tx, asset.id)).toList();
  RateHistory? usdHistory;
  double? usdAt(String d) {
    usdHistory ??= usdHistoryFromTransactions(transactions);
    return usdHistory!.at(d);
  }

  final sorted = orderAssetTxsForReplay(
    assetTxs,
    (tx) => isAcquireForAsset(tx, asset.id),
    (tx) => _readTrade(tx, usdRateFallback, usdAt)?.amount ?? 0,
  );
  final stats = AssetPeriodStats(asset.id);
  final startNum = jalaaliToNumber(period.start);
  final endNum = jalaaliToNumber(period.end);
  var units = 0.0, costToman = 0.0, costUsd = 0.0;
  var shortUnits = 0.0, shortT = 0.0, shortU = 0.0;
  var endUnits = 0.0, endCostT = 0.0, endCostU = 0.0;
  var endSnapshotted = false;
  var poolUnits = 0.0, poolT = 0.0, poolU = 0.0;
  var poolInit = false;
  var missingStartPrice = false;

  void initPool() {
    if (poolInit) return;
    poolInit = true;
    stats.startHoldings = units;
    if (units <= 0) return;
    if (periodStartPrice != null) {
      poolUnits = units;
      poolT = units * periodStartPrice.priceToman;
      poolU = units * periodStartPrice.priceUsd;
    } else {
      missingStartPrice = true;
    }
  }

  for (final tx in sorted) {
    final trade = _readTrade(tx, usdRateFallback, usdAt);
    if (trade == null) {
      stats.invalidTradeCount += 1;
      continue;
    }
    final amount = trade.amount, priceToman = trade.priceToman, priceUsd = trade.priceUsd;
    final txNum = parseDateToNumber(tx.dateString);
    if (txNum >= startNum) initPool();
    if (!endSnapshotted && txNum > endNum) {
      endUnits = units;
      endCostT = costToman;
      endCostU = costUsd;
      endSnapshotted = true;
    }
    final inPeriod = isInPeriod(tx.dateString, period);
    if (isAcquireForAsset(tx, asset.id)) {
      var held = amount;
      if (shortUnits > 0) {
        final cover = math.min(held, shortUnits);
        final avgT = shortT / shortUnits;
        final avgU = shortU / shortUnits;
        if (inPeriod) {
          stats.realizedToman += cover * (avgT - priceToman);
          stats.realizedUsd += cover * (avgU - priceUsd);
          stats.realizedVsCostToman += cover * (avgT - priceToman);
          stats.realizedVsCostUsd += cover * (avgU - priceUsd);
        }
        final before = shortUnits;
        shortUnits -= cover;
        shortT -= cover * avgT;
        shortU -= cover * avgU;
        if (isClosedPosition(shortUnits, before)) {
          shortUnits = 0;
          shortT = 0;
          shortU = 0;
        }
        held -= cover;
        if (isClosedPosition(held, amount)) held = 0;
      }
      units += held;
      costToman += held * priceToman;
      costUsd += held * priceUsd;
      if (inPeriod) {
        initPool();
        poolUnits += held;
        poolT += held * priceToman;
        poolU += held * priceUsd;
        stats.bought.units += amount;
        stats.bought.totalToman += amount * priceToman;
        stats.bought.totalUsd += amount * priceUsd;
        stats.bought.count += 1;
        stats.hadActivity = true;
      }
    } else {
      final avgT = units > 0 ? costToman / units : 0.0;
      final avgU = units > 0 ? costUsd / units : 0.0;
      final drain = math.min(amount, units);
      if (amount > units * (1 + 1e-9) + 1e-15) stats.oversellCount += 1;
      if (inPeriod) {
        initPool();
        final usePool = !missingStartPrice && poolUnits > 0;
        final baseT = usePool ? poolT / poolUnits : avgT;
        final baseU = usePool ? poolU / poolUnits : avgU;
        stats.realizedToman += drain * (priceToman - baseT);
        stats.realizedUsd += drain * (priceUsd - baseU);
        stats.realizedVsCostToman += drain * (priceToman - avgT);
        stats.realizedVsCostUsd += drain * (priceUsd - avgU);
        stats.sold.units += amount;
        stats.sold.totalToman += amount * priceToman;
        stats.sold.totalUsd += amount * priceUsd;
        stats.sold.count += 1;
        stats.hadActivity = true;
        if (drain > 0 && poolUnits > 0) {
          final pAvgT = poolT / poolUnits;
          final pAvgU = poolU / poolUnits;
          final d = math.min(drain, poolUnits);
          final before = poolUnits;
          poolUnits -= d;
          poolT -= d * pAvgT;
          poolU -= d * pAvgU;
          if (isClosedPosition(poolUnits, before)) {
            poolUnits = 0;
            poolT = 0;
            poolU = 0;
          }
        }
      }
      final unitsBefore = units;
      units -= drain;
      costToman -= drain * avgT;
      costUsd -= drain * avgU;
      final excess = amount - drain;
      if (excess > math.max(amount * 1e-9, 1e-15)) {
        shortUnits += excess;
        shortT += excess * priceToman;
        shortU += excess * priceUsd;
      }
      if (isClosedPosition(units, unitsBefore)) {
        units = 0;
        costToman = 0;
        costUsd = 0;
      }
    }
  }
  if (!poolInit) initPool();
  if (!endSnapshotted) {
    endUnits = units;
    endCostT = costToman;
    endCostU = costUsd;
  }
  stats.endHoldings = endUnits;
  stats.endCostBasisToman = endCostT;
  stats.endCostBasisUsd = endCostU;
  stats.endAvgCostToman = endUnits > 0 ? endCostT / endUnits : 0;
  stats.endAvgCostUsd = endUnits > 0 ? endCostU / endUnits : 0;
  stats.currentHoldings = units;
  stats.currentCostBasisToman = costToman;
  stats.currentCostBasisUsd = costUsd;
  stats.currentAvgCostToman = units > 0 ? costToman / units : 0;
  stats.currentAvgCostUsd = units > 0 ? costUsd / units : 0;

  void setEnd(EffectivePrice p) {
    stats.periodEndPriceToman = p.priceToman;
    stats.periodEndPriceUsd = p.priceUsd;
    stats.periodEndPriceSourceDate = p.isLive ? null : p.sourceDate;
    stats.periodEndPriceIsLive = p.isLive;
  }

  if (endUnits <= 0) {
    stats.unrealizedAvailable = true;
  } else if (periodEndPrice != null) {
    stats.unrealizedAvailable = true;
    stats.unrealizedToman = endUnits * periodEndPrice.priceToman - endCostT;
    stats.unrealizedUsd = endUnits * periodEndPrice.priceUsd - endCostU;
    setEnd(periodEndPrice);
  } else {
    stats.unrealizedAvailable = false;
  }
  stats.periodBaselineMissing = missingStartPrice;
  if (stats.startHoldings > 0 && periodStartPrice != null) {
    stats.periodStartPriceToman = periodStartPrice.priceToman;
    stats.periodStartPriceUsd = periodStartPrice.priceUsd;
  }
  if (endUnits <= 0) {
    stats.periodUnrealizedAvailable = true;
  } else if (missingStartPrice) {
    stats.periodUnrealizedAvailable = false;
  } else if (periodEndPrice != null) {
    stats.periodUnrealizedAvailable = true;
    stats.periodUnrealizedToman = endUnits * periodEndPrice.priceToman - poolT;
    stats.periodUnrealizedUsd = endUnits * periodEndPrice.priceUsd - poolU;
    if (stats.periodEndPriceToman == null) setEnd(periodEndPrice);
  } else {
    stats.periodUnrealizedAvailable = false;
  }
  for (final s in [stats.bought, stats.sold]) {
    s.avgPriceToman = s.units > 0 ? s.totalToman / s.units : 0;
    s.avgPriceUsd = s.units > 0 ? s.totalUsd / s.units : 0;
  }
  return stats;
}

// ─── YTD ───────────────────────────────────────────────────────────────────

Period currentJalaliYearPeriod() => clampPeriodToToday(currentPeriod('year'));

AssetPeriodStats ytdUnrealizedForAsset(Asset asset, List<Transaction> txs, List<DailyPrice> dp, double usdRate, String todayStr) {
  final period = currentJalaliYearPeriod();
  final endStr = formatJalaali(period.end);
  final startPrice = effectiveOpeningPriceAt(asset, period.start, dp, todayStr, txs);
  final endPrice = effectivePriceAt(asset, endStr, dp, todayStr, txs);
  return calculateAssetPeriodStats(asset, txs, period, usdRate, endPrice, startPrice);
}

class YtdSummary {
  double totalToman = 0, totalUsd = 0;
  double totalRealizedToman = 0, totalRealizedUsd = 0;
  double totalOpenToman = 0, totalOpenUsd = 0;
  int partialTotalCount = 0, missingStartPriceCount = 0, missingEndPriceCount = 0;
  final List<(Asset, AssetPeriodStats)> rows = [];
}

YtdSummary computeYtdUnrealizedSummary(List<Asset> assets, List<Transaction> txs, List<DailyPrice> dp, double usdRate, String todayStr) {
  final period = currentJalaliYearPeriod();
  final endStr = formatJalaali(period.end);
  final out = YtdSummary();
  for (final asset in assets) {
    if (!asset.includeInProfitLoss) continue;
    final startPrice = effectiveOpeningPriceAt(asset, period.start, dp, todayStr, txs);
    final endPrice = effectivePriceAt(asset, endStr, dp, todayStr, txs);
    final s = calculateAssetPeriodStats(asset, txs, period, usdRate, endPrice, startPrice);
    out.rows.add((asset, s));
    if (s.startHoldings > 0 && startPrice == null) out.missingStartPriceCount += 1;
    if (s.currentHoldings > 0 && endPrice == null) out.missingEndPriceCount += 1;
    out.totalRealizedToman += s.realizedToman;
    out.totalRealizedUsd += s.realizedUsd;
    if (s.periodUnrealizedAvailable) {
      out.totalOpenToman += s.periodUnrealizedToman;
      out.totalOpenUsd += s.periodUnrealizedUsd;
      out.totalToman += s.realizedToman + s.periodUnrealizedToman;
      out.totalUsd += s.realizedUsd + s.periodUnrealizedUsd;
    } else if (s.hadActivity) {
      out.totalToman += s.realizedToman;
      out.totalUsd += s.realizedUsd;
      if (s.currentHoldings > 0) out.partialTotalCount += 1;
    }
  }
  return out;
}

class YtdPnlDisplay {
  final double? total;
  final double realized;
  final double? open;
  final bool isPartial;
  final bool unavailable;
  YtdPnlDisplay(this.total, this.realized, this.open, this.isPartial, this.unavailable);
}

YtdPnlDisplay ytdPnlDisplay(AssetPeriodStats s, String mode) {
  final realized = mode == 'USD' ? s.realizedUsd : s.realizedToman;
  final double? open = s.periodUnrealizedAvailable ? (mode == 'USD' ? s.periodUnrealizedUsd : s.periodUnrealizedToman) : null;
  if (s.periodUnrealizedAvailable) return YtdPnlDisplay(realized + open!, realized, open, s.periodBaselineMissing, false);
  if (s.hadActivity) return YtdPnlDisplay(realized, realized, null, s.currentHoldings > 0, false);
  return YtdPnlDisplay(null, realized, null, s.currentHoldings > 0, true);
}

// ─── Asset P/L (3 numbers) ─────────────────────────────────────────────────

class PnlPart {
  final double toman, usd;
  const PnlPart(this.toman, this.usd);
  static const zero = PnlPart(0, 0);
  double pick(String mode) => mode == 'USD' ? usd : toman;
}

double? pnlPercent(PnlPart value, PnlPart base, String mode) {
  final b = base.pick(mode);
  if (!(b > 0)) return null;
  return value.pick(mode) / b * 100;
}

class AssetPnl {
  final bool included;
  final double holdings;
  final PnlPart activeValue, activeCost;
  final String? activeSince;
  final bool activeAvailable;
  final PnlPart yearValue, yearRealized, yearOpen, yearBase;
  final bool yearPartial, yearEmpty;
  final PnlPart allTimeValue, allTimeRealized, allTimeOpen, allTimeInvested;
  AssetPnl({
    required this.included,
    required this.holdings,
    required this.activeValue,
    required this.activeCost,
    required this.activeSince,
    required this.activeAvailable,
    required this.yearValue,
    required this.yearRealized,
    required this.yearOpen,
    required this.yearBase,
    required this.yearPartial,
    required this.yearEmpty,
    required this.allTimeValue,
    required this.allTimeRealized,
    required this.allTimeOpen,
    required this.allTimeInvested,
  });
}

AssetPnl computeAssetPnl(Asset asset, List<Transaction> txs, List<DailyPrice> dp, double usdRate, String todayStr) {
  final stats = calculateAssetStats(asset, txs, 'TOMAN', usdRate);
  final included = asset.includeInProfitLoss;
  final holdings = stats.totalAmount;
  final activeAvailable = holdings <= 0 || stats.currentPriceSource != 'none';
  final activeValue = holdings > 0 && activeAvailable ? PnlPart(stats.unrealizedProfitToman, stats.unrealizedProfitUsd) : PnlPart.zero;
  final rawRealized = included ? PnlPart(stats.realizedProfitToman, stats.realizedProfitUsd) : PnlPart.zero;
  final ytd = ytdUnrealizedForAsset(asset, txs, dp, usdRate, todayStr);
  final yearRealized = PnlPart(ytd.realizedToman, ytd.realizedUsd);
  final yearOpen = ytd.periodUnrealizedAvailable ? PnlPart(ytd.periodUnrealizedToman, ytd.periodUnrealizedUsd) : PnlPart.zero;
  final yearBase = PnlPart(
    ytd.startHoldings * (ytd.periodStartPriceToman ?? 0) + ytd.bought.totalToman,
    ytd.startHoldings * (ytd.periodStartPriceUsd ?? 0) + ytd.bought.totalUsd,
  );
  final yearEmpty = !ytd.hadActivity && ytd.startHoldings <= 0 && ytd.currentHoldings <= 0;
  return AssetPnl(
    included: included,
    holdings: holdings,
    activeValue: included ? activeValue : PnlPart.zero,
    activeCost: PnlPart(stats.totalCostToman, stats.totalCostUsd),
    activeSince: stats.activeSinceDate,
    activeAvailable: activeAvailable,
    yearValue: included ? PnlPart(yearRealized.toman + yearOpen.toman, yearRealized.usd + yearOpen.usd) : PnlPart.zero,
    yearRealized: included ? yearRealized : PnlPart.zero,
    yearOpen: included ? yearOpen : PnlPart.zero,
    yearBase: yearBase,
    yearPartial: included && (!ytd.periodUnrealizedAvailable || ytd.periodBaselineMissing),
    yearEmpty: yearEmpty,
    allTimeValue: included ? PnlPart(rawRealized.toman + activeValue.toman, rawRealized.usd + activeValue.usd) : PnlPart.zero,
    allTimeRealized: rawRealized,
    allTimeOpen: included ? activeValue : PnlPart.zero,
    allTimeInvested: PnlPart(stats.investedToman, stats.investedUsd),
  );
}

// ─── Portfolio history ─────────────────────────────────────────────────────

double assetNetAmountThroughDate(String assetId, List<Transaction> txs, String through) {
  final limit = parseDateToNumber(through);
  return assetQuantityFromTransactions(assetId, txs.where((t) => parseDateToNumber(t.dateString) <= limit).toList());
}

class PortfolioAssetsValue {
  final double valueToman, valueUsd;
  final int missingPriceCount;
  PortfolioAssetsValue(this.valueToman, this.valueUsd, this.missingPriceCount);
}

PortfolioAssetsValue portfolioAssetsValueAtDate(List<Asset> assets, List<Transaction> txs, List<DailyPrice> dp, String todayStr, String asOf) {
  var t = 0.0, u = 0.0;
  var missing = 0;
  for (final a in assets) {
    if (a.includeInBalance == false) continue;
    final qty = assetNetAmountThroughDate(a.id, txs, asOf);
    if (qty <= 0) continue;
    final p = effectivePriceAt(a, asOf, dp, todayStr, txs);
    if (p == null) {
      missing += 1;
      continue;
    }
    t += qty * p.priceToman;
    u += qty * p.priceUsd;
  }
  return PortfolioAssetsValue(t, u, missing);
}

double portfolioCashTomanAtDate(List<Wallet> wallets, List<Transaction> txs, List<CurrencyRate> rates, String asOf) {
  var cash = 0.0;
  for (final w in wallets) {
    cash += walletBalanceThroughDate(w, txs, asOf) * tomanPerUnit(w.currency, rates);
  }
  return cash;
}

class MonthCashflowPoint {
  final int month;
  final String label;
  double income = 0;
  double expense = 0;
  MonthCashflowPoint(this.month, this.label);
}

double _legacyToman(double? amount, String? walletId, String date, Map<String, Wallet> walletsById, List<CurrencyRate> rates, RateHistories? h) {
  final n = jsNum(amount);
  if (!n.isFinite) return 0;
  final w = walletId == null ? null : walletsById[walletId];
  if (w == null) return 0;
  var rate = tomanPerUnit(w.currency, rates);
  if (w.currency != 'IRT' && h != null) {
    final hist = h[w.currency]?.at(date);
    if (hist != null && hist > 0) rate = hist;
  }
  return n.abs() * (rate > 0 ? rate : 0);
}

/// Toman + USD cashflow value of an INCOME / EXPENSE row, with the same
/// legacy fallbacks the dashboard and yearly chart use.
(double, double) cashflowValueOf(
  Transaction tx,
  Map<String, Wallet> walletsById,
  List<CurrencyRate> rates,
  double usdRate,
  RateHistories? h,
) {
  final isIncome = tx.type == 'INCOME';
  final toman = tx.amountTomanAtTime ??
      _legacyToman(isIncome ? tx.targetAmount : tx.sourceAmount, isIncome ? tx.targetWalletId : tx.sourceWalletId, tx.dateString,
          walletsById, rates, h);
  double usd;
  if (tx.amountUsdAtTime != null) {
    usd = tx.amountUsdAtTime!;
  } else {
    final t = jsNum(tx.amountTomanAtTime);
    final r = jsNum(tx.usdRate);
    if (t.isFinite && t > 0 && r.isFinite && r > 0) {
      usd = t / r;
    } else {
      final hist = h?['USD']?.at(tx.dateString);
      final rate = hist != null && hist > 0 ? hist : usdRate;
      usd = rate > 0 && toman > 0 ? toman / rate : 0;
    }
  }
  return (toman.isFinite ? toman : 0, usd.isFinite ? usd : 0);
}

List<MonthCashflowPoint> buildYearCashflowByMonth(
  List<Transaction> txs,
  List<Wallet> wallets,
  List<CurrencyRate> rates,
  String mode,
  double usdRate,
  RateHistories? h,
) {
  final today = todayJalaali();
  final walletsById = {for (final w in wallets) w.id: w};
  final points = [for (var m = 1; m <= today.jm; m++) MonthCashflowPoint(m, kJalaliMonths[m - 1])];
  for (final tx in txs) {
    if (tx.type != 'INCOME' && tx.type != 'EXPENSE') continue;
    final p = parseJalaali(tx.dateString);
    if (p == null || p.jy != today.jy || p.jm > today.jm) continue;
    final bucket = points[p.jm - 1];
    final (t, u) = cashflowValueOf(tx, walletsById, rates, usdRate, h);
    final v = mode == 'USD' ? u : t;
    if (tx.type == 'INCOME') {
      bucket.income += v;
    } else {
      bucket.expense += v;
    }
  }
  return points;
}
