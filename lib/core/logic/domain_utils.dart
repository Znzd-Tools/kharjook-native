// Ports of goals/utils/*, categories/utils/category-spending-caps.ts,
// deadlines/utils/*, notifications/utils/jalali-days.ts.

import 'dart:math' as math;

import '../models.dart';
import '../utils/digits.dart';
import '../utils/format.dart';
import '../utils/jalali.dart';
import '../utils/period.dart';
import 'ledger.dart';

// ─── Jalali days ────────────────────────────────────────────────────────────

int? daysBetweenJalaali(String from, String to) {
  final a = parseJalaali(from), b = parseJalaali(to);
  if (a == null || b == null) return null;
  final ga = toGregorian(a.jy, a.jm, a.jd), gb = toGregorian(b.jy, b.jm, b.jd);
  return ((DateTime.utc(gb.gy, gb.gm, gb.gd).millisecondsSinceEpoch - DateTime.utc(ga.gy, ga.gm, ga.gd).millisecondsSinceEpoch) / 86400000).round();
}

String dueHint(int? d) {
  if (d == null) return '';
  if (d < 0) return '${toPersianDigits(d.abs())} روز گذشته';
  if (d == 0) return 'امروز';
  if (d == 1) return 'فردا';
  return '${toPersianDigits(d)} روز دیگر';
}

// ─── Schedule ───────────────────────────────────────────────────────────────

JDate _addMonthsClamped(JDate d, int months) {
  final abs = (d.jm - 1) + months;
  final y = d.jy + (abs / 12).floor();
  final m = ((abs % 12) + 12) % 12 + 1;
  return JDate(y, m, math.min(d.jd, jalaaliMonthLength(y, m)));
}

JDate addIntervalDate(JDate d, int n, String period) {
  if (period == 'day') return addDays(d, n);
  if (period == 'week') return addDays(d, n * 7);
  if (period == 'month') return _addMonthsClamped(d, n);
  final y = d.jy + n;
  return JDate(y, d.jm, math.min(d.jd, jalaaliMonthLength(y, d.jm)));
}

JDate nthIntervalDate(JDate anchor, int n, String period, int index) => index == 0 ? anchor : addIntervalDate(anchor, n * index, period);

List<String> buildInstallmentSchedule({required String firstDueDate, required int repeatCount, required int intervalNumber, required String intervalPeriod}) {
  final first = parseJalaali(firstDueDate);
  if (first == null) return [];
  return [for (var i = 0; i < repeatCount; i++) formatJalaali(nthIntervalDate(first, intervalNumber, intervalPeriod, i))];
}

const kIntervalLabels = {'day': 'روز', 'week': 'هفته', 'month': 'ماه', 'year': 'سال'};

// ─── Installments / loans ───────────────────────────────────────────────────

double installmentPaidAmount(LoanInstallment i) => i.paidAmount.isFinite && i.paidAmount > 0 ? i.paidAmount : 0;

double installmentRemainingAmount(LoanInstallment i) {
  final r = i.amount - installmentPaidAmount(i);
  return !r.isFinite || r <= 0 ? 0 : r;
}

bool installmentHasPartialPay(LoanInstallment i) => !i.isPaid && installmentPaidAmount(i) > 0;

String? validatePartialPayAmount(double pay, double remaining) {
  if (!pay.isFinite || pay <= 0) return 'مبلغ پرداخت نامعتبر است.';
  if (pay > remaining + 1e-9) return 'مبلغ از باقی‌مانده قسط بیشتر است.';
  return null;
}

String canonicalInstallmentAmount(double n) {
  if (!n.isFinite || n <= 0) return '';
  var s = n.toStringAsFixed(10);
  s = s.replaceAll(RegExp(r'\.?0+$'), '');
  return s.isEmpty ? '0' : s;
}

double loanAmountToToman(double amount, String currency, String? assetId, List<CurrencyRate> rates, Map<String, Asset> assetsById) {
  if (!(amount > 0)) return 0;
  if (assetId != null) {
    final p = assetsById[assetId]?.priceToman ?? 0;
    return p > 0 ? amount * p : 0;
  }
  final r = tomanPerUnit(currency, rates);
  return r > 0 ? amount * r : 0;
}

const kLoanReminderDayOptions = [1, 3, 7, 14];

List<int> normalizeReminderDaysBefore(List<int> v) => (v.where((d) => d > 0 && d <= 90).toSet().toList()..sort());

String reminderDaysLabel(List<int> days) {
  final n = normalizeReminderDaysBefore(days);
  if (n.isEmpty) return 'فقط روز سررسید';
  return n.map((d) => '$d روز قبل').join('، ');
}

// ─── Subscriptions amount ──────────────────────────────────────────────────

double subscriptionAmountToToman(double amount, String currency, List<CurrencyRate> rates) {
  final r = tomanPerUnit(currency, rates);
  return r > 0 ? amount * r : 0;
}

double subscriptionConvertedAmount(double amount, String currency, String mode, List<CurrencyRate> rates, double usdRate) {
  final t = subscriptionAmountToToman(amount, currency, rates);
  if (!(t > 0)) return amount;
  if (mode == 'USD' && usdRate > 0) return t / usdRate;
  return t;
}

const _symbols = {'IRT': 'ت', 'USD': '\$', 'TRY': '₺', 'EUR': '€'};
String formatSubscriptionNativeAmount(double amount, String currency) => '${_symbols[currency] ?? currency} ${formatCurrencyAmount(amount, currency)}';
String formatSubscriptionConvertedLabel(double amount, String currency, String mode, List<CurrencyRate> rates, double usdRate) =>
    formatCurrency(subscriptionConvertedAmount(amount, currency, mode, rates, usdRate), mode);

// ─── Spending caps ─────────────────────────────────────────────────────────

class CapStatus {
  final String categoryId, categoryName, categoryColor;
  final double limitToman, spentToman, percent;
  final String level; // ok | warn | over
  CapStatus(this.categoryId, this.categoryName, this.categoryColor, this.limitToman, this.spentToman, this.percent, this.level);
}

String capLevelForPercent(double p) => p >= 100 ? 'over' : (p >= 80 ? 'warn' : 'ok');

Set<String> collectDescendantCategoryIds(List<Category> categories, String rootId, [String kind = 'expense']) {
  final scoped = categories.where((c) => c.kind == kind).toList();
  final ids = <String>{rootId};
  var changed = true;
  while (changed) {
    changed = false;
    for (final c in scoped) {
      if (c.parentId != null && ids.contains(c.parentId) && !ids.contains(c.id)) {
        ids.add(c.id);
        changed = true;
      }
    }
  }
  return ids;
}

double sumCategoryExpenseToman(List<Transaction> txs, Set<String> ids, Period period) {
  var total = 0.0;
  for (final tx in txs) {
    if (tx.type != 'EXPENSE' || tx.categoryId == null || !ids.contains(tx.categoryId)) continue;
    if (!isInPeriod(tx.dateString, period)) continue;
    final v = tx.amountTomanAtTime ?? 0;
    if (v.isFinite && v > 0) total += v;
  }
  return total;
}

List<CapStatus> buildCapStatuses({required List<CategorySpendingCap> caps, required List<Category> categories, required List<Transaction> transactions, required Period period}) {
  final byId = {for (final c in categories) c.id: c};
  final out = <CapStatus>[];
  for (final cap in caps) {
    final c = byId[cap.categoryId];
    if (c == null || c.kind != 'expense') continue;
    if (!(cap.monthlyLimitToman > 0)) continue;
    final spent = sumCategoryExpenseToman(transactions, collectDescendantCategoryIds(categories, cap.categoryId), period);
    final pct = spent / cap.monthlyLimitToman * 100;
    out.add(CapStatus(cap.categoryId, c.name, c.color, cap.monthlyLimitToman, spent, pct, capLevelForPercent(pct)));
  }
  return stableSorted(out, (a, b) => b.percent.compareTo(a.percent));
}

double sumCategoryCapsToman(List<CategorySpendingCap> caps, List<Category> categories, [String kind = 'expense']) {
  final scoped = {for (final c in categories.where((c) => c.kind == kind)) c.id: c};
  final capped = caps.where((c) => scoped.containsKey(c.categoryId) && c.monthlyLimitToman > 0).map((c) => c.categoryId).toSet();
  bool hasCappedAncestor(String id) {
    final seen = <String>{id};
    var pid = scoped[id]?.parentId;
    while (pid != null && scoped.containsKey(pid) && !seen.contains(pid)) {
      if (capped.contains(pid)) return true;
      seen.add(pid);
      pid = scoped[pid]?.parentId;
    }
    return false;
  }

  var total = 0.0;
  for (final cap in caps) {
    if (!scoped.containsKey(cap.categoryId)) continue;
    if (!cap.monthlyLimitToman.isFinite || cap.monthlyLimitToman <= 0) continue;
    if (hasCappedAncestor(cap.categoryId)) continue;
    total += cap.monthlyLimitToman;
  }
  return total;
}

String monthKeyFromPeriod(Period p) => '${p.start.jy}/${p.start.jm.toString().padLeft(2, '0')}';

// ─── Goals ─────────────────────────────────────────────────────────────────

const kGoalPercentTolerance = 0.5;

String goalValueKindFromGoal(String targetKind) => targetKind == 'quantity' ? 'quantity' : 'percent';

bool isGoalMet(double current, double target, String kind) {
  if (target <= 0) return current <= 0;
  final delta = current - target;
  if (kind == 'percent') return delta.abs() <= kGoalPercentTolerance;
  return delta.abs() <= target * (kGoalPercentTolerance / 100);
}

String formatGoalValue(double v, String kind, String unit) {
  if (!v.isFinite) return '—';
  if (kind == 'percent') return '${toFixed(v, 1)}%';
  final f = formatEnNumber(v, maxFrac: 4);
  return unit.isNotEmpty ? '$f $unit' : f;
}

class GoalProgress {
  final double current, target, percentComplete, remaining;
  final double? currentPortfolioPercent;
  GoalProgress(this.current, this.target, this.percentComplete, this.remaining, [this.currentPortfolioPercent]);
}

class GoalDelta {
  final String status; // under | met | over
  final double delta;
  final String label;
  GoalDelta(this.status, this.delta, this.label);
}

GoalDelta computeGoalDelta(GoalProgress? p, String kind, String unit) {
  if (p == null || p.target <= 0) return GoalDelta('under', 0, '—');
  final delta = p.current - p.target;
  if (isGoalMet(p.current, p.target, kind)) return GoalDelta('met', delta, 'رسیده');
  if (delta > 0) {
    final a = kind == 'percent' ? '+${toFixed(delta, 1)}%' : '+${formatGoalValue(delta, 'quantity', unit)}';
    return GoalDelta('over', delta, '$a بالاتر');
  }
  final abs = delta.abs();
  final a = kind == 'percent' ? '−${toFixed(abs, 1)}%' : '−${formatGoalValue(abs, 'quantity', unit)}';
  return GoalDelta('under', delta, '$a پایین‌تر');
}

GoalProgress progressOf(double current, double target) =>
    GoalProgress(current, target, target > 0 ? current / target * 100 : 0, math.max(0, target - current));

GoalProgress clampGoalProgress(double current, double target) {
  final c = current.isFinite ? math.max(0.0, current) : 0.0;
  final t = target.isFinite ? math.max(0.0, target) : 0.0;
  return GoalProgress(c, t, t > 0 ? math.min(999.0, c / t * 100) : 0, math.max(0, t - c));
}

class GoalBarMetrics {
  final double targetPct, currentPct, baseFillPct, overflowPct;
  final bool showOverflow;
  GoalBarMetrics(this.targetPct, this.currentPct, this.baseFillPct, this.overflowPct, this.showOverflow);
}

GoalBarMetrics computeGoalBarMetricsForKind(GoalProgress? p, String kind) {
  if (p == null || p.target <= 0) return GoalBarMetrics(100, 0, 0, 0, false);
  final scaleMax = p.current > p.target ? math.max(p.target, p.current) * 1.06 : p.target;
  final t = p.target / scaleMax * 100, c = p.current / scaleMax * 100;
  return GoalBarMetrics(t, c, math.min(c, t), p.current > p.target ? c - t : 0, p.current > p.target && !isGoalMet(p.current, p.target, kind));
}

String goalGapLabel(GoalProgress? p, String kind, String unit) {
  if (p == null || p.target <= 0) return '—';
  if (isGoalMet(p.current, p.target, kind)) return '۰';
  return formatGoalValue((p.current - p.target).abs(), kind, unit);
}

class AssetSnapshot {
  final Asset asset;
  final double quantity, valueToman, valueUsd;
  final bool includedInBalance;
  AssetSnapshot(this.asset, this.quantity, this.valueToman, this.valueUsd, this.includedInBalance);
}

List<AssetSnapshot> buildAssetSnapshots(List<Asset> assets, List<Transaction> txs, String mode, double usdRate) => assets.map((a) {
      final s = calculateAssetStats(a, txs, mode, usdRate);
      return AssetSnapshot(a, s.totalAmount, s.currentValueToman, s.currentValueUsd, a.includeInBalance != false);
    }).toList();

double totalSnapshotValueToman(List<AssetSnapshot> s) => s.fold(0.0, (sum, r) => sum + (r.includedInBalance ? math.max(0.0, r.valueToman) : 0));

GoalProgress? calculateAssetGoalProgress(Goal g, List<AssetSnapshot> snaps, double total) {
  AssetSnapshot? snap;
  for (final s in snaps) {
    if (s.asset.id == g.assetId) snap = s;
  }
  if (snap == null) return null;
  if (g.targetKind == 'quantity') return clampGoalProgress(snap.quantity, g.targetQuantity ?? 0);
  final pct = snap.includedInBalance && total > 0 ? math.max(0.0, snap.valueToman) / total * 100 : 0.0;
  final p = clampGoalProgress(pct, g.targetPercent ?? 0);
  return GoalProgress(p.current, p.target, p.percentComplete, p.remaining, pct);
}

GoalProgress? calculateGroupGoalProgress(Goal g, List<AssetSnapshot> snaps, double total) {
  if (g.categoryId == null || g.targetKind != 'allocation_percent') return null;
  final gv = snaps.fold(0.0, (s, r) => r.includedInBalance && r.asset.categoryId == g.categoryId ? s + math.max(0.0, r.valueToman) : s);
  final pct = total > 0 ? gv / total * 100 : 0.0;
  final p = clampGoalProgress(pct, g.targetPercent ?? 0);
  return GoalProgress(p.current, p.target, p.percentComplete, p.remaining, pct);
}

String goalTargetLabel(Goal g) =>
    g.targetKind == 'quantity' ? formatEnNumber(g.targetQuantity ?? 0) : '${toFixed(g.targetPercent ?? 0, 1)}%';

double? computeBuyOnlyValueToman(double current, double portfolio, double target) {
  if (target <= 0 || target >= 100 || !current.isFinite || !portfolio.isFinite) return null;
  final num = target * portfolio - 100 * current;
  return num <= 0 ? null : num / (100 - target);
}

double? computeSellOnlyValueToman(double current, double portfolio, double target) {
  if (target <= 0 || target >= 100 || !current.isFinite || !portfolio.isFinite) return null;
  final num = 100 * current - target * portfolio;
  return num <= 0 ? null : num / (100 - target);
}

class GoalActionInput {
  final String name, kind;
  final double current, target;
  final String? unit;
  final int? decimalPlaces;
  final double? currentValueToman, portfolioValueToman, priceToman, usdRate, maxQuantity;
  final String? currencyMode;
  final bool allowSell;
  GoalActionInput({
    required this.name,
    required this.kind,
    required this.current,
    required this.target,
    this.unit,
    this.decimalPlaces,
    this.currentValueToman,
    this.portfolioValueToman,
    this.priceToman,
    this.usdRate,
    this.maxQuantity,
    this.currencyMode,
    this.allowSell = false,
  });
}

String _qty(double v, int dp) => formatEnNumber(v, maxFrac: dp, minFrac: 0);
String _money(double toman, String mode, double usd) => formatCurrency(mode == 'USD' && usd > 0 ? toman / usd : toman, mode);

/// Returns (action, message) or null.
(String, String)? buildGoalActionSuggestion(GoalActionInput i) {
  if (i.target <= 0 || isGoalMet(i.current, i.target, i.kind)) return null;
  final unitSuffix = (i.unit ?? '').isNotEmpty ? ' ${i.unit}' : '';
  final dp = i.decimalPlaces ?? 4;
  final mode = i.currencyMode ?? 'TOMAN';
  if (i.current < i.target) {
    if (i.kind == 'quantity') {
      final q = math.max(0.0, i.target - i.current);
      if (q <= 0) return null;
      return ('buy', '${_qty(q, dp)}$unitSuffix ${i.name} بیشتر بخر');
    }
    final t = computeBuyOnlyValueToman(i.currentValueToman ?? 0, i.portfolioValueToman ?? 0, i.target);
    if (t == null || t <= 0) return null;
    final p = i.priceToman ?? 0;
    if (p > 0) return ('buy', '${_qty(t / p, dp)}$unitSuffix ${i.name} بیشتر بخر');
    return ('buy', 'حدود ${_money(t, mode, i.usdRate ?? 0)} از ${i.name} بخر');
  }
  if (i.allowSell && i.current > i.target) {
    if (i.kind == 'quantity') {
      final q = math.max(0.0, i.current - i.target);
      if (q <= 0) return null;
      final capped = i.maxQuantity != null ? math.min(q, math.max(0.0, i.maxQuantity!)) : q;
      if (capped <= 0) return null;
      return ('sell', '${_qty(capped, dp)}$unitSuffix ${i.name} بفروش');
    }
    final t = computeSellOnlyValueToman(i.currentValueToman ?? 0, i.portfolioValueToman ?? 0, i.target);
    if (t == null || t <= 0) return null;
    final p = i.priceToman ?? 0;
    if (p > 0) {
      var q = t / p;
      if (i.maxQuantity != null) q = math.min(q, math.max(0.0, i.maxQuantity!));
      if (q <= 0) return null;
      return ('sell', '${_qty(q, dp)}$unitSuffix ${i.name} بفروش');
    }
    return ('sell', 'حدود ${_money(t, mode, i.usdRate ?? 0)} از ${i.name} بفروش');
  }
  return null;
}

String? buildGoalBuySuggestion(GoalActionInput i) => buildGoalActionSuggestion(GoalActionInput(
      name: i.name,
      kind: i.kind,
      current: i.current,
      target: i.target,
      unit: i.unit,
      decimalPlaces: i.decimalPlaces,
      currentValueToman: i.currentValueToman,
      portfolioValueToman: i.portfolioValueToman,
      priceToman: i.priceToman,
      usdRate: i.usdRate,
      currencyMode: i.currencyMode,
    ))?.$2;

class GoalDriftRow {
  final String id, name, kindLabel, valueKind, deltaLabel;
  final double currentValue, targetValue;
  final String? actionSuggestion;
  GoalDriftRow(this.id, this.name, this.kindLabel, this.valueKind, this.currentValue, this.targetValue, this.deltaLabel, this.actionSuggestion);
}

List<GoalDriftRow> buildGoalDriftRows({
  required List<Goal> goals,
  required List<Asset> assets,
  required List<Category> categories,
  required List<Transaction> transactions,
  required String currencyMode,
  required double usdRate,
}) {
  final catById = {for (final c in categories) c.id: c};
  final valueById = <String, double>{};
  final mainDist = <String, double>{};
  var total = 0.0;
  final statsById = <String, AssetStats>{};
  for (final a in assets) {
    final s = calculateAssetStats(a, transactions, currencyMode, usdRate);
    statsById[a.id] = s;
    if (a.includeInBalance == false) continue;
    total += s.currentValueToman;
    if (s.currentValueToman > 0) {
      valueById[a.id] = s.currentValueToman;
      final k = a.categoryId ?? '__uncat__';
      mainDist[k] = (mainDist[k] ?? 0) + s.currentValueToman;
    }
  }
  Asset? assetOf(String? id) {
    for (final a in assets) {
      if (a.id == id) return a;
    }
    return null;
  }

  final rows = <GoalDriftRow>[];
  for (final g in goals) {
    final vk = goalValueKindFromGoal(g.targetKind);
    if (g.targetKind == 'quantity') {
      if (g.scope != 'asset') continue;
      final a = assetOf(g.assetId);
      if (a == null) continue;
      final target = g.targetQuantity ?? 0;
      if (!target.isFinite || target <= 0) continue;
      final cur = statsById[a.id]!.totalAmount;
      final sug = buildGoalActionSuggestion(GoalActionInput(
          name: a.name, kind: 'quantity', current: cur, target: target, unit: a.unit, decimalPlaces: a.decimalPlaces, maxQuantity: cur, allowSell: true));
      rows.add(GoalDriftRow(g.id, a.name, 'دارایی', vk, cur, target, computeGoalDelta(progressOf(cur, target), vk, a.unit).label, sug?.$2));
      continue;
    }
    final target = g.targetPercent ?? 0;
    if (!target.isFinite || target <= 0) continue;
    if (g.scope == 'asset') {
      final a = assetOf(g.assetId);
      if (a == null) continue;
      final cvt = valueById[a.id] ?? 0;
      final cur = total > 0 ? cvt / total * 100 : 0.0;
      final sug = buildGoalActionSuggestion(GoalActionInput(
        name: a.name,
        kind: 'percent',
        current: cur,
        target: target,
        currentValueToman: cvt,
        portfolioValueToman: total,
        priceToman: a.priceToman,
        unit: a.unit,
        decimalPlaces: a.decimalPlaces,
        currencyMode: currencyMode,
        usdRate: usdRate,
        maxQuantity: statsById[a.id]!.totalAmount,
        allowSell: true,
      ));
      rows.add(GoalDriftRow(g.id, a.name, 'دارایی', vk, cur, target, computeGoalDelta(progressOf(cur, target), vk, '%').label, sug?.$2));
      continue;
    }
    final c = g.categoryId == null ? null : catById[g.categoryId];
    if (c == null) continue;
    final gv = mainDist[c.id] ?? 0;
    final cur = total > 0 ? gv / total * 100 : 0.0;
    final sug = buildGoalActionSuggestion(GoalActionInput(
        name: c.name, kind: 'percent', current: cur, target: target, currentValueToman: gv, portfolioValueToman: total, currencyMode: currencyMode, usdRate: usdRate, allowSell: true));
    rows.add(GoalDriftRow(g.id, c.name, 'گروه', vk, cur, target, computeGoalDelta(progressOf(cur, target), vk, '%').label, sug?.$2));
  }
  return rows;
}

List<GoalDriftRow> filterDriftedGoalRows(List<GoalDriftRow> rows) => rows.where((r) => !isGoalMet(r.currentValue, r.targetValue, r.valueKind)).toList();
List<GoalDriftRow> sortGoalDriftRows(List<GoalDriftRow> rows) =>
    stableSorted(rows, (a, b) => (b.currentValue - b.targetValue).abs().compareTo((a.currentValue - a.targetValue).abs()));

// ─── Recurring due dates (plan/utils/recurring-due-in-period.ts) ────────────

int compareJalaaliStrings(String a, String b) {
  final pa = parseJalaali(a), pb = parseJalaali(b);
  if (pa == null || pb == null) return a.compareTo(b);
  return cmpJalaali(pa, pb);
}

JDate subtractIntervalDate(JDate date, int n, String period) {
  if (period == 'day') return addDays(date, -n);
  if (period == 'week') return addDays(date, -n * 7);
  if (period == 'month') {
    final abs = date.jm - 1 - n;
    final y = date.jy + (abs / 12).floor();
    final m = ((abs % 12) + 12) % 12 + 1;
    return JDate(y, m, math.min(date.jd, jalaaliMonthLength(y, m)));
  }
  final y = date.jy - n;
  return JDate(y, date.jm, math.min(date.jd, jalaaliMonthLength(y, date.jm)));
}

List<String> dueDatesInPeriod(String dateString, int intervalNumber, String intervalPeriod, Period period, {String? endDateString}) {
  final anchor = parseJalaali(dateString);
  if (anchor == null) return [];
  String at(int i) => formatJalaali(nthIntervalDate(anchor, intervalNumber, intervalPeriod, i));
  final start = formatJalaali(period.start), end = formatJalaali(period.end);
  var index = 0;
  while (index < 500 && compareJalaaliStrings(at(index), start) < 0) {
    index++;
  }
  final dates = <String>[];
  for (var i = 0; i < 500; i++, index++) {
    final due = at(index);
    if (endDateString != null && endDateString.isNotEmpty && compareJalaaliStrings(due, endDateString) > 0) break;
    if (compareJalaaliStrings(due, end) > 0) break;
    if (isInPeriod(due, period)) dates.add(due);
  }
  return dates;
}

List<String> recurringDueDatesInPeriod(RecurringTransaction r, Period period) {
  if (!r.isActive || r.deletedAt != null) return [];
  return dueDatesInPeriod(r.nextDueDateString, r.intervalNumber, r.intervalPeriod, period, endDateString: r.endDateString);
}

List<String> subscriptionDueDatesInPeriod(Subscription s, Period period) {
  if (s.status != 'active' || s.deletedAt != null) return [];
  return dueDatesInPeriod(s.nextDueDateString, s.intervalNumber, s.intervalPeriod, period);
}

JDate rewindRecurringAnchor(JDate anchor, int n, String period, JDate periodStart) {
  final ps = formatJalaali(periodStart);
  var cursor = anchor;
  for (var i = 0; i < 500; i++) {
    if (compareJalaaliStrings(formatJalaali(cursor), ps) < 0) return cursor;
    cursor = subtractIntervalDate(cursor, n, period);
  }
  return cursor;
}

String intervalLabel(int n, String period) {
  final unit = period == 'day' ? 'روز' : period == 'week' ? 'هفته' : period == 'month' ? 'ماه' : 'سال';
  return n == 1 ? 'هر $unit' : 'هر $n $unit';
}
