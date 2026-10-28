// Port of HomeTab.tsx and its widgets.

import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/router.dart';
import '../../core/logic/domain_utils.dart';
import '../../core/logic/ledger.dart';
import '../../core/logic/pnl.dart';
import '../../core/models.dart';
import '../../core/store.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/widgets.dart';
import '../../core/utils/digits.dart';
import '../../core/utils/format.dart';
import '../../core/utils/jalali.dart';
import '../../core/utils/period.dart';

const _palette = [Color(0xFF8B5CF6), Color(0xFF06B6D4), Color(0xFF22C55E), Color(0xFFF59E0B), Color(0xFFEF4444), Color(0xFFEC4899)];

class _GoalRow {
  final String id, name, kindLabel, valueKind;
  final double currentValue, targetValue;
  final String? unit, buySuggestion;
  _GoalRow(this.id, this.name, this.kindLabel, this.valueKind, this.currentValue, this.targetValue, this.unit, this.buySuggestion);
}

class _Named {
  final String id, name;
  final double valueToman;
  _Named(this.id, this.name, this.valueToman);
}

class _OpenRow {
  final String id, name;
  final double pnlToman, pnlUsd, costToman, costUsd;
  _OpenRow(this.id, this.name, this.pnlToman, this.pnlUsd, this.costToman, this.costUsd);
}

class _Stats {
  double totalPortfolioToman = 0, cashToman = 0;
  final List<(String, String)> walletsMissingRate = [], walletsOnHistoryRate = [];
  double openPnlToman = 0, openPnlUsd = 0, openCostToman = 0, openCostUsd = 0, allTimeToman = 0, allTimeUsd = 0;
  final List<_OpenRow> openRows = [];
  double yearPnlToman = 0, yearPnlUsd = 0;
  int yearPnlPartialCount = 0, yearUnrealizedMissingCount = 0;
  double monthIncomeToman = 0, monthIncomeUsd = 0, monthExpenseToman = 0, monthExpenseUsd = 0;
  (String, double)? maxExpenseToman, maxExpenseUsd;
  List<_Named> mainDistribution = [], subDistribution = [];
  List<_GoalRow> goalComparison = [];
}

_Stats _computeStats(PortfolioStore s, String todayS, Period monthPeriod) {
  final st = _Stats();
  final mode = s.currencyMode;
  final usdRate = s.usdRate;
  final h = s.rateHistories;
  final catById = {for (final c in s.categories) c.id: c};
  final walletsById = {for (final w in s.wallets) w.id: w};
  final byCat = <String, double>{}, byCatUsd = <String, double>{};
  final mainMap = <String, double>{};
  final assetValueById = <String, double>{};
  var assetsValueToman = 0.0;
  final ms = formatJalaali(monthPeriod.start), me = formatJalaali(monthPeriod.end);

  for (final tx in s.transactions) {
    if (tx.dateString.compareTo(ms) < 0 || tx.dateString.compareTo(me) > 0) continue;
    if (tx.type != 'INCOME' && tx.type != 'EXPENSE') continue;
    final (t, u) = cashflowValueOf(tx, walletsById, s.currencyRates, usdRate, h);
    if (tx.type == 'INCOME') {
      st.monthIncomeToman += t;
      st.monthIncomeUsd += u;
    } else {
      st.monthExpenseToman += t;
      st.monthExpenseUsd += u;
      final k = tx.categoryId ?? '__uncat__';
      byCat[k] = (byCat[k] ?? 0) + t;
      byCatUsd[k] = (byCatUsd[k] ?? 0) + u;
    }
  }

  for (final a in s.assets) {
    final as = calculateAssetStats(a, s.transactions, mode, usdRate);
    final pnl = computeAssetPnl(a, s.transactions, s.dailyPrices, usdRate, todayS);
    if (pnl.included) {
      st.allTimeToman += pnl.allTimeValue.toman;
      st.allTimeUsd += pnl.allTimeValue.usd;
      if (pnl.holdings > 0 && pnl.activeCost.toman > 0) {
        st.openPnlToman += pnl.activeValue.toman;
        st.openPnlUsd += pnl.activeValue.usd;
        st.openCostToman += pnl.activeCost.toman;
        st.openCostUsd += pnl.activeCost.usd;
        st.openRows.add(_OpenRow(a.id, a.name, pnl.activeValue.toman, pnl.activeValue.usd, pnl.activeCost.toman, pnl.activeCost.usd));
      }
    }
    if (a.includeInBalance != false) assetsValueToman += as.currentValueToman;
    if (as.currentValueToman > 0 && a.includeInBalance != false) {
      st.subDistribution.add(_Named(a.id, a.name, as.currentValueToman));
      assetValueById[a.id] = as.currentValueToman;
      final k = a.categoryId ?? '__uncat__';
      mainMap[k] = (mainMap[k] ?? 0) + as.currentValueToman;
    }
  }

  for (final w in s.wallets) {
    final bal = calculateWalletStats(w, s.transactions).balance;
    final r = walletRateNow(w.currency, s.currencyRates, h);
    if (bal != 0 && r.source == 'missing') st.walletsMissingRate.add((w.name, w.currency));
    if (bal != 0 && r.source == 'history') st.walletsOnHistoryRate.add((w.name, w.currency));
    st.cashToman += bal * r.rate;
  }
  st.totalPortfolioToman = assetsValueToman + st.cashToman;

  final ytd = computeYtdUnrealizedSummary(s.assets, s.transactions, s.dailyPrices, usdRate, todayS);
  st.yearPnlToman = ytd.totalToman;
  st.yearPnlUsd = ytd.totalUsd;
  st.yearPnlPartialCount = ytd.partialTotalCount;
  st.yearUnrealizedMissingCount = ytd.missingStartPriceCount + ytd.missingEndPriceCount;

  String catName(String id) => id == '__uncat__' ? 'بدون دسته' : (catById[id]?.name ?? 'بدون دسته');
  st.mainDistribution = stableSorted(mainMap.entries.map((e) => _Named(e.key, catName(e.key), e.value)), (a, b) => b.valueToman.compareTo(a.valueToman));
  st.subDistribution = stableSorted(st.subDistribution, (a, b) => b.valueToman.compareTo(a.valueToman));

  Asset? assetOf(String? id) {
    for (final a in s.assets) {
      if (a.id == id) return a;
    }
    return null;
  }

  final goals = <_GoalRow>[];
  for (final g in s.goals) {
    if (g.targetKind == 'quantity') {
      if (g.scope != 'asset') continue;
      final a = assetOf(g.assetId);
      if (a == null) continue;
      final target = g.targetQuantity ?? 0;
      if (!target.isFinite || target <= 0) continue;
      final cur = calculateAssetStats(a, s.transactions, mode, usdRate).totalAmount;
      goals.add(_GoalRow(g.id, a.name, 'دارایی', 'quantity', cur, target, a.unit,
          buildGoalBuySuggestion(GoalActionInput(name: a.name, kind: 'quantity', current: cur, target: target, unit: a.unit, decimalPlaces: a.decimalPlaces))));
      continue;
    }
    final target = g.targetPercent ?? 0;
    if (!target.isFinite || target <= 0) continue;
    if (g.scope == 'asset') {
      final a = assetOf(g.assetId);
      if (a == null) continue;
      final cvt = assetValueById[a.id] ?? 0;
      final pct = assetsValueToman > 0 ? cvt / assetsValueToman * 100 : 0.0;
      goals.add(_GoalRow(
          g.id,
          a.name,
          'دارایی',
          'percent',
          pct,
          target,
          a.unit,
          buildGoalBuySuggestion(GoalActionInput(
              name: a.name,
              kind: 'percent',
              current: pct,
              target: target,
              currentValueToman: cvt,
              portfolioValueToman: assetsValueToman,
              priceToman: a.priceToman,
              unit: a.unit,
              decimalPlaces: a.decimalPlaces,
              currencyMode: mode,
              usdRate: usdRate))));
      continue;
    }
    final c = g.categoryId == null ? null : catById[g.categoryId];
    if (c == null) continue;
    final gv = mainMap[c.id] ?? 0;
    final pct = assetsValueToman > 0 ? gv / assetsValueToman * 100 : 0.0;
    goals.add(_GoalRow(g.id, c.name, 'گروه', 'percent', pct, target, null,
        buildGoalBuySuggestion(GoalActionInput(name: c.name, kind: 'percent', current: pct, target: target, currentValueToman: gv, portfolioValueToman: assetsValueToman, currencyMode: mode, usdRate: usdRate))));
  }
  st.goalComparison = stableSorted(goals, (a, b) => b.targetValue.compareTo(a.targetValue));

  (String, double)? maxOf(Map<String, double> m) {
    if (m.isEmpty) return null;
    final e = stableSorted(m.entries, (a, b) => b.value.compareTo(a.value)).first;
    return (catName(e.key), e.value);
  }

  st.maxExpenseToman = maxOf(byCat);
  st.maxExpenseUsd = maxOf(byCatUsd);
  return st;
}

String _signed(double v, String mode) => '${v >= 0 ? '+' : ''}${formatCurrency(v, mode)}';
String _signedPct(double v) => '${v >= 0 ? '+' : ''}${toFixed(v, 1)}%';

String? formatMissingPriceWarning(int missing, int partial) {
  if (missing <= 0 && partial <= 0) return null;
  final parts = <String>[];
  if (missing > 0) parts.add('${formatDisplayNumber(missing)} دارایی بدون قیمت تاریخی؛');
  if (partial > 0) parts.add('${formatDisplayNumber(partial)} دارایی فقط با سود محقق‌شده.');
  if (missing > 0) parts.add('عدد سال ممکن است ناقص باشد.');
  return parts.join(' ');
}

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});
  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  bool refreshing = false;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<PortfolioStore>();
    final mode = s.currencyMode;
    final usdRate = s.usdRate;
    final today = todayJalaali();
    final todayS = formatJalaali(today);
    final monthPeriod = clampPeriodToToday(currentPeriod('month'));
    final st = _computeStats(s, todayS, monthPeriod);

    double conv(double t) => mode == 'USD' && usdRate > 0 ? t / usdRate : t;
    final displayPortfolio = mode == 'USD' ? (usdRate > 0 ? st.totalPortfolioToman / usdRate : 0.0) : st.totalPortfolioToman;
    final displayCash = mode == 'USD' ? (usdRate > 0 ? st.cashToman / usdRate : 0.0) : st.cashToman;
    final assetsToman = math.max(0.0, st.totalPortfolioToman - st.cashToman);
    final displayAssets = conv(assetsToman);
    final assetShare = st.totalPortfolioToman > 0 ? assetsToman / st.totalPortfolioToman * 100 : 0.0;
    final cashShare = st.totalPortfolioToman > 0 ? st.cashToman / st.totalPortfolioToman * 100 : 0.0;
    final openPnl = mode == 'USD' ? st.openPnlUsd : st.openPnlToman;
    final openCost = mode == 'USD' ? st.openCostUsd : st.openCostToman;
    final openPct = openCost > 0 ? openPnl / openCost * 100 : 0.0;
    final movers = stableSorted(
            st.openRows.map((r) {
              final v = mode == 'USD' ? r.pnlUsd : r.pnlToman;
              final c = mode == 'USD' ? r.costUsd : r.costToman;
              return (r.id, r.name, v, c > 0 ? v / c * 100 : 0.0);
            }),
            (a, b) => b.$3.abs().compareTo(a.$3.abs()))
        .take(3)
        .toList();
    final monthBalance = mode == 'USD' ? st.monthIncomeUsd - st.monthExpenseUsd : st.monthIncomeToman - st.monthExpenseToman;
    final maxExp = mode == 'USD' ? st.maxExpenseUsd : st.maxExpenseToman;

    // Price ticker items.
    final ticker = <(String, String, String)>[];
    if (usdRate > 0) ticker.add(('دلار', formatCurrency(usdRate, 'TOMAN'), '/prices'));
    for (final a in s.assets) {
      final as = calculateAssetStats(a, s.transactions, mode, usdRate);
      if (as.totalAmount <= 0) continue;
      final p = mode == 'USD' ? a.priceUsd : a.priceToman;
      if (!p.isFinite || p <= 0) continue;
      ticker.add((a.unit.isNotEmpty ? '${a.name} / ${a.unit}' : a.name, formatCurrency(p, mode), '/assets/${a.id}'));
    }

    // Deadlines this month.
    final monthKey = '${today.jy}/${today.jm.toString().padLeft(2, '0')}/';
    final monthRows = s.upcomingDeadlines.where((i) => i.dueDateString.startsWith(monthKey)).map((i) {
      final rate = tomanPerUnit(i.loanCurrency ?? 'IRT', s.currencyRates);
      final amount = conv(installmentRemainingAmount(i) * (rate > 0 ? rate : 0));
      return (i.loanTitle ?? 'بدهی', formatJalaaliHuman(parseJalaali(i.dueDateString) ?? today), amount);
    }).toList();
    final monthTotal = monthRows.fold(0.0, (a, r) => a + r.$3);

    final goalRows = stableSorted(st.goalComparison, (a, b) {
      final ma = isGoalMet(a.currentValue, a.targetValue, a.valueKind);
      final mb = isGoalMet(b.currentValue, b.targetValue, b.valueKind);
      if (ma != mb) return ma ? 1 : -1;
      return (b.currentValue - b.targetValue).abs().compareTo((a.currentValue - a.targetValue).abs());
    }).take(6).toList();

    final mainTotal = st.mainDistribution.fold(0.0, (a, r) => a + r.valueToman);
    final yearCash = buildYearCashflowByMonth(s.transactions, s.wallets, s.currencyRates, mode, usdRate, s.rateHistories);

    return RefreshIndicator(
      onRefresh: s.refreshAll,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
        if (s.dataFetchError)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AppCard(
              borderColor: C.rose.withValues(alpha: 0.3),
              color: Color.alphaBlend(C.rose.withValues(alpha: 0.08), C.raised),
              child: Row(children: [
                const Expanded(child: Text('خطا در دریافت اطلاعات از سرور.', style: TextStyle(color: C.rose300, fontSize: 13))),
                AppButton('تلاش مجدد', variant: BtnVariant.danger, dense: true, onPressed: s.refresh),
              ]),
            ),
          ),
        Row(children: [
          const Expanded(child: Text('داشبورد', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white))),
          Text(s.isLoadingData ? 'در حال به‌روزرسانی...' : 'به‌روز', style: const TextStyle(fontSize: 11, color: C.slate500)),
          const SizedBox(width: 8),
          IconBtn(
            Icons.refresh,
            tooltip: 'بروزرسانی قیمت‌ها',
            size: 16,
            onTap: s.isLoadingData || refreshing
                ? null
                : () async {
                    setState(() => refreshing = true);
                    await s.refreshAll();
                    if (mounted) setState(() => refreshing = false);
                  },
          ),
        ]),
        const SizedBox(height: 14),
        _HeroCard(
          total: formatCurrency(displayPortfolio, mode),
          assets: formatCurrency(displayAssets, mode),
          cash: formatCurrency(displayCash, mode),
          assetShare: assetShare,
          cashShare: cashShare,
        ),
        if (st.walletsMissingRate.isNotEmpty || st.walletsOnHistoryRate.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: AppCard(
              onTap: () => Nav.push(context, '/prices'),
              borderColor: C.amber.withValues(alpha: 0.3),
              color: Color.alphaBlend(C.amber.withValues(alpha: 0.08), C.raised),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (st.walletsMissingRate.isNotEmpty)
                  Text(
                      'نرخ ${st.walletsMissingRate.map((w) => w.$2).toSet().join('، ')} ثبت نشده؛ ${formatDisplayNumber(st.walletsMissingRate.length)} کیف پول در جمع کل حساب نشده.',
                      style: const TextStyle(fontSize: 12, color: C.amber300, height: 1.6)),
                if (st.walletsOnHistoryRate.isNotEmpty)
                  Text('نرخ ${st.walletsOnHistoryRate.map((w) => w.$2).toSet().join('، ')} ثبت نشده؛ با آخرین نرخ شناخته‌شده حساب شد.',
                      style: const TextStyle(fontSize: 12, color: C.amber300, height: 1.6)),
                const Text('برای ثبت نرخ بزن.', style: TextStyle(fontSize: 11, color: C.slate400)),
              ]),
            ),
          ),
        const SizedBox(height: 12),
        _ActivePnlCard(
          mode: mode,
          openValue: openPnl,
          openPercent: openPct,
          openCost: openCost,
          yearValue: mode == 'USD' ? st.yearPnlUsd : st.yearPnlToman,
          allTimeValue: mode == 'USD' ? st.allTimeUsd : st.allTimeToman,
          movers: movers,
          warning: formatMissingPriceWarning(st.yearUnrealizedMissingCount, st.yearPnlPartialCount),
        ),
        if (ticker.isNotEmpty) ...[const SizedBox(height: 12), _Ticker(items: ticker)],
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _QuickLink(icon: Icons.bar_chart, label: 'گزارش‌ها', onTap: () => Nav.push(context, '/reports'))),
          const SizedBox(width: 10),
          Expanded(child: _QuickLink(icon: Icons.trending_up, label: 'قیمت‌ها و نرخ‌ها', onTap: () => Nav.push(context, '/prices'))),
        ]),
        const SizedBox(height: 12),
        _MonthlyCashflowChart(months: yearCash, mode: mode, yearLabel: 'سال ${toPersianDigits(today.jy)}'),
        _CapsWidget(store: s),
        _GoalsDriftWidget(store: s),
        _PendingChecksWidget(store: s),
        _PendingSubsWidget(store: s),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: _MetricCard(
              title: 'بالانس ماه',
              value: '${monthBalance >= 0 ? '+' : ''}${formatCurrency(monthBalance, mode)}',
              tone: monthBalance >= 0 ? C.emerald300 : C.rose300,
              icon: Icons.auto_awesome,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _MetricCard(
              title: 'بیشترین هزینه ماه',
              value: maxExp != null ? formatCurrency(maxExp.$2, mode) : '—',
              subtitle: maxExp?.$1 ?? 'بدون داده',
              tone: C.rose300,
              icon: Icons.pie_chart_outline,
            ),
          ),
        ]),
        const SizedBox(height: 12),
        AppCard(
          onTap: () => Nav.push(context, '/deadlines'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: C.amber.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.event_note, size: 16, color: C.amber300),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('سررسید', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                  Text('پرداخت‌های نزدیک همین ماه', style: TextStyle(fontSize: 11, color: C.slate500)),
                ]),
              ),
              if (monthRows.isNotEmpty) Text('${formatDisplayNumber(monthRows.length)} مورد', style: const TextStyle(fontSize: 11, color: C.amber300)),
            ]),
            const SizedBox(height: 12),
            if (monthRows.isEmpty)
              const Text('سررسید پرداخت‌نشده‌ای وجود ندارد', style: TextStyle(fontSize: 12, color: C.slate500))
            else ...[
              Row(children: [
                Expanded(child: Text('${kJalaliMonths[today.jm - 1]} ${toPersianDigits(today.jy)}', style: const TextStyle(fontSize: 12, color: C.slate400))),
                Money(formatCurrency(monthTotal, mode), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: C.amber300)),
              ]),
              const SizedBox(height: 8),
              for (final r in monthRows)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r.$1, style: const TextStyle(fontSize: 13, color: C.slate200)),
                        Text(r.$2, style: const TextStyle(fontSize: 11, color: C.slate500)),
                      ]),
                    ),
                    Money(formatCurrency(r.$3, mode), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: C.slate300)),
                  ]),
                ),
            ],
          ]),
        ),
        const SizedBox(height: 12),
        _GoalsSection(rows: goalRows),
        const SizedBox(height: 12),
        _TopAllocation(
          rows: st.mainDistribution.take(3).map((r) => (r.name, conv(r.valueToman), mainTotal > 0 ? r.valueToman / mainTotal * 100 : 0.0)).toList(),
          mode: mode,
        ),
        const SizedBox(height: 12),
        _DistributionCard(
            title: 'توزیع گروه‌ها',
            subtitle: 'گروه‌های بزرگ‌تر در سبد',
            rows: st.mainDistribution.take(6).map((r) => (r.name, conv(r.valueToman), formatCurrency(conv(r.valueToman), mode))).toList()),
        const SizedBox(height: 12),
        _DistributionCard(
            title: 'توزیع دارایی‌ها',
            subtitle: 'دارایی‌های غالب',
            rows: st.subDistribution.take(6).map((r) => (r.name, conv(r.valueToman), formatCurrency(conv(r.valueToman), mode))).toList()),
        const SizedBox(height: 12),
        AppCard(
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: C.cyan.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.account_balance_wallet_outlined, size: 18, color: C.cyan300),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('نقدی', style: TextStyle(fontSize: 11, color: C.slate400)),
                Money(formatCurrency(displayCash, mode), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
                Text('${toFixed(cashShare, 1)}% از پورتفو', style: const TextStyle(fontSize: 11, color: C.slate500)),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _HeroCard extends StatelessWidget {
  final String total, assets, cash;
  final double assetShare, cashShare;
  const _HeroCard({required this.total, required this.assets, required this.cash, required this.assetShare, required this.cashShare});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: C.purple500.withValues(alpha: 0.2)),
        gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [C.purple.withValues(alpha: 0.28), C.raised, C.raised]),
      ),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: C.white10, borderRadius: BorderRadius.circular(999)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.auto_awesome, size: 13, color: C.purple300),
                  SizedBox(width: 4),
                  Text('نمای کلی سبد', style: TextStyle(fontSize: 11, color: C.purple300)),
                ]),
              ),
              const SizedBox(height: 10),
              const Text('ارزش کل پورتفو', style: TextStyle(fontSize: 12, color: C.slate400)),
              const SizedBox(height: 2),
              FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Money(total, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white))),
            ]),
          ),
          SizedBox(
            width: 76,
            height: 76,
            child: Stack(alignment: Alignment.center, children: [
              PieChart(PieChartData(
                sectionsSpace: 0,
                centerSpaceRadius: 26,
                startDegreeOffset: -90,
                sections: [
                  PieChartSectionData(value: math.max(assetShare, 0.0001), color: C.violet, radius: 10, showTitle: false),
                  PieChartSectionData(value: math.max(cashShare, 0.0001), color: C.cyan, radius: 10, showTitle: false),
                  if (assetShare + cashShare < 100) PieChartSectionData(value: 100 - assetShare - cashShare, color: C.white10, radius: 10, showTitle: false),
                ],
              )),
              Money('${toFixed(assetShare, 0)}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _SplitPill(label: 'دارایی‌ها', value: assets, percent: assetShare, color: C.violet)),
          const SizedBox(width: 10),
          Expanded(child: _SplitPill(label: 'نقدی', value: cash, percent: cashShare, color: C.cyan)),
        ]),
      ]),
    );
  }
}

class _SplitPill extends StatelessWidget {
  final String label, value;
  final double percent;
  final Color color;
  const _SplitPill({required this.label, required this.value, required this.percent, required this.color});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(16), border: Border.all(color: C.borderSoft)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 11, color: C.slate400))),
            Money('${toFixed(percent, 1)}%', style: TextStyle(fontSize: 11, color: color)),
          ]),
          const SizedBox(height: 4),
          Money(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 8),
          _Bar(percent: percent, color: color),
        ]),
      );
}

class _Bar extends StatelessWidget {
  final double percent;
  final Color color;
  final double height;
  const _Bar({required this.percent, required this.color, this.height = 5});
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: height,
          color: C.white5,
          alignment: AlignmentDirectional.centerStart,
          child: FractionallySizedBox(widthFactor: (percent.isFinite ? percent : 0).clamp(0, 100) / 100, child: Container(color: color)),
        ),
      );
}

class _ActivePnlCard extends StatelessWidget {
  final String mode;
  final double openValue, openPercent, openCost, yearValue, allTimeValue;
  final List<(String, String, double, double)> movers;
  final String? warning;
  const _ActivePnlCard({required this.mode, required this.openValue, required this.openPercent, required this.openCost, required this.yearValue, required this.allTimeValue, required this.movers, this.warning});
  @override
  Widget build(BuildContext context) {
    final pos = openValue >= 0;
    final tone = pos ? C.emerald300 : C.rose300;
    final accent = pos ? C.emerald : C.rose;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
        gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [accent.withValues(alpha: 0.12), C.raised, C.raised]),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('سود/زیان باز', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
              Text('روی دارایی‌هایی که الان داری', style: TextStyle(fontSize: 11, color: C.slate500)),
            ]),
          ),
          TextButton(
            onPressed: () => Nav.push(context, '/assets'),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Text('دارایی‌ها', style: TextStyle(fontSize: 12, color: C.slate300)),
              Icon(Icons.chevron_left, size: 16, color: C.slate400),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        if (openCost > 0)
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Money(_signed(openValue, mode), style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: tone)),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(999)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(pos ? Icons.trending_up : Icons.trending_down, size: 13, color: tone),
                const SizedBox(width: 3),
                Money(_signedPct(openPercent), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tone)),
              ]),
            ),
          ])
        else
          const Text('فعلاً دارایی بازی نداری.', style: TextStyle(fontSize: 13, color: C.slate400)),
        if (openCost > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(children: [
              const Text('روی سرمایه‌ی ', style: TextStyle(fontSize: 11, color: C.slate500)),
              Money(formatCurrency(openCost, mode), style: const TextStyle(fontSize: 11, color: C.slate400)),
            ]),
          ),
        if (movers.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final m in movers)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: InkWell(
                onTap: () => Nav.push(context, '/assets/${m.$1}'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    Expanded(child: Text(m.$2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: C.slate300))),
                    Money('${_signed(m.$3, mode)} · ${_signedPct(m.$4)}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: m.$3 >= 0 ? C.emerald300 : C.rose300)),
                  ]),
                ),
              ),
            ),
        ],
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _MiniPnl(label: 'سود/زیان امسال', value: _signed(yearValue, mode), positive: yearValue >= 0)),
          const SizedBox(width: 10),
          Expanded(child: _MiniPnl(label: 'سود/زیان از ابتدا', value: _signed(allTimeValue, mode), positive: allTimeValue >= 0)),
        ]),
        if (warning != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(warning!, style: const TextStyle(fontSize: 11, color: C.amber300, height: 1.6))),
      ]),
    );
  }
}

class _MiniPnl extends StatelessWidget {
  final String label, value;
  final bool positive;
  const _MiniPnl({required this.label, required this.value, required this.positive});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 10, color: C.slate500)),
          Money(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: (positive ? C.emerald300 : C.rose300).withValues(alpha: 0.85))),
        ]),
      );
}

class _Ticker extends StatefulWidget {
  final List<(String, String, String)> items;
  const _Ticker({required this.items});
  @override
  State<_Ticker> createState() => _TickerState();
}

class _TickerState extends State<_Ticker> {
  final _c = ScrollController();
  Timer? _t;
  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(milliseconds: 40), (_) {
      if (!_c.hasClients) return;
      final max = _c.position.maxScrollExtent;
      if (max <= 0) return;
      var next = _c.offset + 0.6;
      if (next >= max / 2) next = 0;
      _c.jumpTo(next);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loop = [...widget.items, ...widget.items];
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14),
          child: Row(children: [
            Icon(Icons.trending_up, size: 14, color: C.purple400),
            SizedBox(width: 6),
            Text('قیمت لحظه‌ای', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: C.slate300)),
          ]),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 52,
          child: ListView.separated(
            controller: _c,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: loop.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => InkWell(
              onTap: () => Nav.push(context, loop[i].$3),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: C.white5, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.borderSoft)),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(loop[i].$1, style: const TextStyle(fontSize: 10, color: C.slate500)),
                  Money(loop[i].$2, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _QuickLink extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickLink({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(12),
        onTap: onTap,
        radius: 16,
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(color: C.purple500.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: C.purple400),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: C.slate200))),
          const Icon(Icons.chevron_left, size: 18, color: C.slate500),
        ]),
      );
}

class _MonthlyCashflowChart extends StatelessWidget {
  final List<MonthCashflowPoint> months;
  final String mode, yearLabel;
  const _MonthlyCashflowChart({required this.months, required this.mode, required this.yearLabel});
  @override
  Widget build(BuildContext context) {
    final maxV = math.max(1.0, months.fold(0.0, (m, p) => math.max(m, math.max(p.income, p.expense))));
    final ti = months.fold(0.0, (a, p) => a + p.income);
    final te = months.fold(0.0, (a, p) => a + p.expense);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('درآمد و هزینه', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
              Text(yearLabel, style: const TextStyle(fontSize: 11, color: C.slate500)),
            ]),
          ),
          TextButton(
            onPressed: () => Nav.push(context, '/reports/cashflow'),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Text('گزارش کامل', style: TextStyle(fontSize: 12, color: C.purple400)),
              Icon(Icons.chevron_left, size: 16, color: C.purple400),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _sum(Icons.arrow_circle_up_outlined, 'جمع درآمد', formatCurrency(ti, mode), C.emerald300)),
          const SizedBox(width: 10),
          Expanded(child: _sum(Icons.arrow_circle_down_outlined, 'جمع هزینه', formatCurrency(te, mode), C.rose300)),
        ]),
        const SizedBox(height: 14),
        if (months.isEmpty)
          const Text('تراکنش درآمد/هزینه‌ای ثبت نشده.', style: TextStyle(fontSize: 12, color: C.slate500))
        else ...[
          SizedBox(
            height: 140,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (final p in months)
                  Expanded(
                    child: Tooltip(
                      message: 'درآمد: ${formatCurrency(p.income, mode)}\nهزینه: ${formatCurrency(p.expense, mode)}',
                      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                        Expanded(
                          child: Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.center, children: [
                            _vbar(p.income, maxV, C.emerald400),
                            const SizedBox(width: 2),
                            _vbar(p.expense, maxV, C.rose400),
                          ]),
                        ),
                        const SizedBox(height: 4),
                        Text(p.label, maxLines: 1, overflow: TextOverflow.clip, style: const TextStyle(fontSize: 8, color: C.slate500)),
                      ]),
                    ),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Dot(C.emerald400, size: 8),
            SizedBox(width: 4),
            Text('درآمد', style: TextStyle(fontSize: 11, color: C.slate400)),
            SizedBox(width: 14),
            Dot(C.rose400, size: 8),
            SizedBox(width: 4),
            Text('هزینه', style: TextStyle(fontSize: 11, color: C.slate400)),
          ]),
        ],
      ]),
    );
  }

  Widget _vbar(double v, double max, Color c) => LayoutBuilder(builder: (_, cons) {
        final h = v > 0 ? math.max(cons.maxHeight * 0.04, cons.maxHeight * v / max) : 0.0;
        return Container(width: 7, height: h, decoration: BoxDecoration(color: c.withValues(alpha: 0.85), borderRadius: const BorderRadius.vertical(top: Radius.circular(3))));
      });

  Widget _sum(IconData i, String l, String v, Color c) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(14), border: Border.all(color: c.withValues(alpha: 0.15))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(i, size: 13, color: c), const SizedBox(width: 4), Text(l, style: const TextStyle(fontSize: 11, color: C.slate400))]),
          const SizedBox(height: 4),
          Money(v, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c)),
        ]),
      );
}

Widget _widgetHeader(BuildContext context, IconData icon, Color color, String title, String subtitle, String action, String href) => Row(children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, size: 16, color: color),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
          Text(subtitle, style: const TextStyle(fontSize: 11, color: C.slate500)),
        ]),
      ),
      TextButton(
        onPressed: () => Nav.push(context, href),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(action, style: const TextStyle(fontSize: 12, color: C.slate300)),
          const Icon(Icons.chevron_left, size: 16, color: C.slate400),
        ]),
      ),
    ]);

class _CapsWidget extends StatelessWidget {
  final PortfolioStore store;
  const _CapsWidget({required this.store});
  @override
  Widget build(BuildContext context) {
    if (store.spendingCaps.isEmpty) return const SizedBox.shrink();
    final rows = buildCapStatuses(caps: store.spendingCaps, categories: store.categories, transactions: store.transactions, period: clampPeriodToToday(currentPeriod('month'))).take(5).toList();
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _widgetHeader(context, Icons.track_changes, C.amber300, 'سقف هزینه ماه', 'پیشرفت دسته‌های محدودشده', 'مدیریت', '/manage/categories'),
          const SizedBox(height: 10),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Dot(hexColor(r.categoryColor), size: 8),
                  const SizedBox(width: 6),
                  Expanded(child: Text(r.categoryName, style: const TextStyle(fontSize: 12, color: C.slate200))),
                  Text('${toPersianDigits(r.percent.round())}٪', style: const TextStyle(fontSize: 12, color: C.slate300)),
                ]),
                const SizedBox(height: 6),
                _Bar(
                  percent: r.percent <= 0 ? 0 : math.max(math.min(r.percent, 100), 4),
                  color: r.level == 'over' ? C.rose : (r.level == 'warn' ? C.amber : C.emerald),
                  height: 6,
                ),
                const SizedBox(height: 4),
                Money('${formatCurrency(r.spentToman, 'TOMAN')} / ${formatCurrency(r.limitToman, 'TOMAN')}', style: const TextStyle(fontSize: 10, color: C.slate500)),
              ]),
            ),
        ]),
      ),
    );
  }
}

class _GoalsDriftWidget extends StatelessWidget {
  final PortfolioStore store;
  const _GoalsDriftWidget({required this.store});
  @override
  Widget build(BuildContext context) {
    final s = store;
    final rows = sortGoalDriftRows(filterDriftedGoalRows(buildGoalDriftRows(
            goals: s.goals, assets: s.assets, categories: s.categories, transactions: s.transactions, currencyMode: s.currencyMode, usdRate: s.usdRate)))
        .take(5)
        .toList();
    if (rows.isEmpty) return const SizedBox.shrink();
    String axis(GoalDriftRow r) => r.valueKind == 'percent'
        ? '${toFixed(r.currentValue, 1)}% ← ${toFixed(r.targetValue, 1)}%'
        : '${formatEnNumber(r.currentValue)} ← ${formatEnNumber(r.targetValue)}';
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _widgetHeader(context, Icons.track_changes, C.purple400, 'انحراف از اهداف', '${toPersianDigits(rows.length)} مورد نیازمند تنظیم', 'اهداف', '/manage/goals'),
          for (final r in rows)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: C.white5, borderRadius: BorderRadius.circular(14)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: Text('${r.name} · ${r.kindLabel}', style: const TextStyle(fontSize: 12, color: C.slate200))),
                  Text(r.deltaLabel, style: const TextStyle(fontSize: 11, color: C.amber300)),
                ]),
                Money(axis(r), style: const TextStyle(fontSize: 11, color: C.slate400)),
                if (r.actionSuggestion != null) Text('💡 ${r.actionSuggestion}', style: const TextStyle(fontSize: 11, color: C.purple300)),
              ]),
            ),
        ]),
      ),
    );
  }
}

Color _dueTone(int? d) {
  if (d == null) return C.slate400;
  if (d < 0) return C.rose400;
  if (d == 0) return C.amber300;
  if (d <= 7) return const Color(0xE6FDE68A);
  return C.slate400;
}

class _PendingChecksWidget extends StatelessWidget {
  final PortfolioStore store;
  const _PendingChecksWidget({required this.store});
  @override
  Widget build(BuildContext context) {
    final s = store;
    final pending = s.checks.where((c) => c.status == 'pending').toList();
    if (pending.isEmpty) return const SizedBox.shrink();
    final todayS = todayStr();
    final rows = stableSorted(pending, (a, b) => a.dueDateString.compareTo(b.dueDateString)).take(5).toList();
    final overdue = rows.where((c) => (daysBetweenJalaali(todayS, c.dueDateString) ?? 0) < 0).length;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _widgetHeader(context, Icons.receipt_long_outlined, C.sky400, 'چک‌های در انتظار',
              '${toPersianDigits(pending.length)} مورد${overdue > 0 ? ' · ${toPersianDigits(overdue)} معوق' : ''}', 'همه', '/deadlines/checks'),
          for (final c in rows)
            Builder(builder: (_) {
              final rate = tomanPerUnit(c.currency, s.currencyRates);
              final t = c.amount * (rate > 0 ? rate : 0);
              final amt = s.currencyMode == 'USD' && s.usdRate > 0 ? t / s.usdRate : t;
              final d = daysBetweenJalaali(todayS, c.dueDateString);
              final due = parseJalaali(c.dueDateString);
              return InkWell(
                onTap: () => Nav.push(context, '/deadlines/checks'),
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(c.title, style: const TextStyle(fontSize: 13, color: C.slate200)),
                        Text('${due != null ? formatJalaaliHuman(due) : c.dueDateString}${c.bankName != null ? ' · ${c.bankName}' : ''}', style: const TextStyle(fontSize: 11, color: C.slate500)),
                        if (dueHint(d).isNotEmpty) Text(dueHint(d), style: TextStyle(fontSize: 10, color: _dueTone(d))),
                      ]),
                    ),
                    Money(formatCurrency(amt, s.currencyMode), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: C.slate300)),
                  ]),
                ),
              );
            }),
        ]),
      ),
    );
  }
}

class SubscriptionAmountText extends StatelessWidget {
  final double amount;
  final String currency;
  final PortfolioStore store;
  final double size;
  const SubscriptionAmountText({super.key, required this.amount, required this.currency, required this.store, this.size = 12});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Money(formatSubscriptionConvertedLabel(amount, currency, store.currencyMode, store.currencyRates, store.usdRate),
            style: TextStyle(fontSize: size, fontWeight: FontWeight.w700, color: C.slate300)),
        if (currency != 'IRT') Money(formatSubscriptionNativeAmount(amount, currency), style: const TextStyle(fontSize: 10, color: C.slate500)),
      ]);
}

class _PendingSubsWidget extends StatelessWidget {
  final PortfolioStore store;
  const _PendingSubsWidget({required this.store});
  @override
  Widget build(BuildContext context) {
    final s = store;
    final active = s.activeSubscriptions.where((r) => r.status == 'active').toList();
    if (active.isEmpty) return const SizedBox.shrink();
    final todayS = todayStr();
    final rows = stableSorted(active, (a, b) => a.nextDueDateString.compareTo(b.nextDueDateString)).take(5).toList();
    final overdue = rows.where((r) => (daysBetweenJalaali(todayS, r.nextDueDateString) ?? 0) < 0).length;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _widgetHeader(context, Icons.repeat, C.cyan300, 'اشتراک‌های نزدیک',
              '${toPersianDigits(active.length)} مورد${overdue > 0 ? ' · ${toPersianDigits(overdue)} معوق' : ''}', 'همه', '/deadlines/subscriptions'),
          for (final r in rows)
            Builder(builder: (_) {
              final d = daysBetweenJalaali(todayS, r.nextDueDateString);
              final due = parseJalaali(r.nextDueDateString);
              return InkWell(
                onTap: () => Nav.push(context, '/deadlines/subscriptions'),
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r.platform, style: const TextStyle(fontSize: 13, color: C.slate200)),
                        Text(due != null ? formatJalaaliHuman(due) : r.nextDueDateString, style: const TextStyle(fontSize: 11, color: C.slate500)),
                        if (dueHint(d).isNotEmpty) Text(dueHint(d), style: TextStyle(fontSize: 10, color: _dueTone(d))),
                      ]),
                    ),
                    SubscriptionAmountText(amount: r.amount, currency: r.currency, store: s),
                  ]),
                ),
              );
            }),
        ]),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title, value;
  final String? subtitle;
  final Color tone;
  final IconData icon;
  const _MetricCard({required this.title, required this.value, this.subtitle, required this.tone, required this.icon});
  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 11, color: C.slate400)),
                Money(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: tone)),
              ]),
            ),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: tone.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, size: 14, color: tone),
            ),
          ]),
          if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(subtitle!, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: C.slate500))),
        ]),
      );
}

class _GoalsSection extends StatelessWidget {
  final List<_GoalRow> rows;
  const _GoalsSection({required this.rows});
  @override
  Widget build(BuildContext context) {
    final met = rows.where((r) => isGoalMet(r.currentValue, r.targetValue, r.valueKind)).length;
    final pending = rows.length - met;
    final buys = rows.where((r) => r.buySuggestion != null).toList();
    final maxV = math.max(1.0, rows.fold(0.0, (m, r) => math.max(m, math.max(r.currentValue, r.targetValue))));
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.track_changes, size: 16, color: C.purple400),
          const SizedBox(width: 6),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('هدف‌های سبد', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
              Text(rows.isNotEmpty ? '${formatDisplayNumber(met)} از ${formatDisplayNumber(rows.length)} رسیده' : 'هدفی تعریف نشده', style: const TextStyle(fontSize: 11, color: C.slate500)),
            ]),
          ),
          TextButton(
            onPressed: () => Nav.push(context, '/manage/goals'),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Text('مدیریت', style: TextStyle(fontSize: 12, color: C.slate300)),
              Icon(Icons.chevron_left, size: 16, color: C.slate400),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        if (rows.isEmpty)
          const Row(children: [
            Icon(Icons.error_outline, size: 12, color: C.slate500),
            SizedBox(width: 6),
            Expanded(child: Text('از بخش مدیریت، هدف برای دارایی یا گروه تعریف کن.', style: TextStyle(fontSize: 12, color: C.slate500))),
          ])
        else ...[
          Row(children: [
            Expanded(child: _countBox(Icons.check_circle_outline, 'رسیده به هدف', met, C.emerald300)),
            const SizedBox(width: 10),
            Expanded(child: _countBox(Icons.radio_button_unchecked, 'در انتظار', pending, C.amber300)),
          ]),
          const SizedBox(height: 14),
          SizedBox(
            height: 130,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (final r in rows)
                  Expanded(
                    child: Column(children: [
                      Expanded(
                        child: LayoutBuilder(builder: (_, c) {
                          final status = computeGoalDelta(progressOf(r.currentValue, r.targetValue), r.valueKind, r.valueKind == 'percent' ? '%' : (r.unit ?? '')).status;
                          double hOf(double v) => v > 0 ? math.max(c.maxHeight * 0.04, c.maxHeight * v / maxV) : 0;
                          return Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Container(width: 12, height: hOf(r.currentValue), decoration: BoxDecoration(color: (status == 'under' ? C.rose : C.emerald).withValues(alpha: 0.85), borderRadius: const BorderRadius.vertical(top: Radius.circular(4)))),
                            const SizedBox(width: 2),
                            Container(width: 12, height: hOf(r.targetValue), decoration: BoxDecoration(border: Border.all(color: C.slate400.withValues(alpha: 0.6)), borderRadius: const BorderRadius.vertical(top: Radius.circular(4)))),
                          ]);
                        }),
                      ),
                      const SizedBox(height: 4),
                      Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9, color: C.slate400)),
                    ]),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Dot(C.emerald, size: 8),
            SizedBox(width: 4),
            Text('رسیده', style: TextStyle(fontSize: 10, color: C.slate400)),
            SizedBox(width: 10),
            Dot(C.rose, size: 8),
            SizedBox(width: 4),
            Text('کمتر از هدف', style: TextStyle(fontSize: 10, color: C.slate400)),
            SizedBox(width: 10),
            Dot(C.slate400, size: 8),
            SizedBox(width: 4),
            Text('هدف', style: TextStyle(fontSize: 10, color: C.slate400)),
          ]),
          if (buys.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: C.purple500.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: C.purple500.withValues(alpha: 0.2))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('پیشنهاد خرید', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: C.purple300)),
                for (final r in buys) Padding(padding: const EdgeInsets.only(top: 4), child: Text('• ${r.buySuggestion}', style: const TextStyle(fontSize: 12, color: C.slate300))),
              ]),
            ),
          ],
        ],
      ]),
    );
  }

  Widget _countBox(IconData i, String l, int v, Color c) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(i, size: 13, color: c), const SizedBox(width: 4), Text(l, style: const TextStyle(fontSize: 11, color: C.slate400))]),
          Text(formatDisplayNumber(v), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c)),
        ]),
      );
}

class _TopAllocation extends StatelessWidget {
  final List<(String, double, double)> rows;
  final String mode;
  const _TopAllocation({required this.rows, required this.mode});
  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const AppCard(child: Text('دارایی‌ای در سبد ثبت نشده.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: C.slate500)));
    }
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('بیشترین سهم سبد', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(rows[i].$1, style: const TextStyle(fontSize: 12, color: C.slate200))),
                Money('${formatCurrency(rows[i].$2, mode)} · ${toFixed(rows[i].$3, 1)}%', style: const TextStyle(fontSize: 11, color: C.slate400)),
              ]),
              const SizedBox(height: 6),
              _Bar(percent: math.min(100, rows[i].$3), color: _palette[i % 3], height: 6),
            ]),
          ),
      ]),
    );
  }
}

class _DistributionCard extends StatelessWidget {
  final String title, subtitle;
  final List<(String, double, String)> rows;
  const _DistributionCard({required this.title, required this.subtitle, required this.rows});
  @override
  Widget build(BuildContext context) {
    final total = rows.fold(0.0, (a, r) => a + r.$2);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.pie_chart_outline, size: 16, color: C.purple400),
          const SizedBox(width: 6),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
              Text(subtitle, style: const TextStyle(fontSize: 11, color: C.slate500)),
            ]),
          ),
          if (rows.isNotEmpty)
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              const Text('بیشترین', style: TextStyle(fontSize: 10, color: C.slate500)),
              Text(rows.first.$1, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: C.slate200)),
            ]),
        ]),
        const SizedBox(height: 14),
        if (rows.isEmpty)
          const Row(children: [Icon(Icons.error_outline, size: 12, color: C.slate500), SizedBox(width: 6), Text('بدون داده', style: TextStyle(fontSize: 12, color: C.slate500))])
        else
          Row(children: [
            SizedBox(
              width: 110,
              height: 110,
              child: Stack(alignment: Alignment.center, children: [
                PieChart(PieChartData(
                  sectionsSpace: 1,
                  centerSpaceRadius: 34,
                  startDegreeOffset: -90,
                  sections: total > 0
                      ? [for (var i = 0; i < rows.length; i++) PieChartSectionData(value: rows[i].$2, color: _palette[i % _palette.length], radius: 18, showTitle: false)]
                      : [PieChartSectionData(value: 1, color: C.white10, radius: 18, showTitle: false)],
                )),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('کل', style: TextStyle(fontSize: 10, color: C.slate500)),
                  Text(toPersianDigits(rows.length), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                ]),
              ]),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(children: [
                for (var i = 0; i < rows.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        Dot(_palette[i % _palette.length], size: 8),
                        const SizedBox(width: 5),
                        Expanded(child: Text(rows[i].$1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: C.slate300))),
                        Money(total > 0 ? '${toFixed(rows[i].$2 / total * 100, 1)}%' : '0.0%', style: const TextStyle(fontSize: 10, color: C.slate400)),
                      ]),
                      Money(rows[i].$3, style: const TextStyle(fontSize: 10, color: C.slate500)),
                      const SizedBox(height: 3),
                      _Bar(percent: total > 0 ? rows[i].$2 / total * 100 : 0, color: _palette[i % _palette.length], height: 4),
                    ]),
                  ),
              ]),
            ),
          ]),
      ]),
    );
  }
}
