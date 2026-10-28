// Port of ReportsIndexView.tsx.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/router.dart';
import '../../core/logic/pnl.dart';
import '../../core/store.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/widgets.dart';
import '../../core/utils/digits.dart';
import '../../core/utils/format.dart';
import '../../core/utils/jalali.dart';
import '../../core/utils/period.dart';
import '../transactions/tx_logic.dart';
import 'report_logic.dart';

const _scopes = ['month', 'year', 'all'];

/// Sum of realized + period-unrealized P&L across P&L-included assets.
(double, double, int) assetsPnlTotal(PortfolioStore s, Period period, String todayS) {
  final endStr = formatJalaali(period.end);
  double t = 0, u = 0;
  var missing = 0;
  for (final a in s.assets) {
    if (!a.includeInProfitLoss) continue;
    final startPrice = period.kind == 'all' ? null : effectiveOpeningPriceAt(a, period.start, s.dailyPrices, todayS, s.transactions);
    final endPrice = effectivePriceAt(a, endStr, s.dailyPrices, todayS, s.transactions);
    final st = calculateAssetPeriodStats(a, s.transactions, period, s.usdRate, endPrice, startPrice);
    t += st.realizedToman;
    u += st.realizedUsd;
    if (st.periodUnrealizedAvailable) {
      t += st.periodUnrealizedToman;
      u += st.periodUnrealizedUsd;
    } else if (st.currentHoldings > 0 || st.endHoldings > 0) {
      missing++;
    }
  }
  return (t, u, missing);
}

class ReportsIndexScreen extends StatefulWidget {
  const ReportsIndexScreen({super.key});
  @override
  State<ReportsIndexScreen> createState() => _ReportsIndexScreenState();
}

class _ReportsIndexScreenState extends State<ReportsIndexScreen> {
  String scope = 'month';

  @override
  Widget build(BuildContext context) {
    final s = context.watch<PortfolioStore>();
    final mode = s.currencyMode;
    final todayS = todayStr();
    final period = clampPeriodToToday(currentPeriod(scope));

    (double, double, double) cash(Period p) {
      final i = rollupCategories(transactions: s.transactions, categories: s.categories, period: p, kind: 'income', currencyMode: mode).total;
      final e = rollupCategories(transactions: s.transactions, categories: s.categories, period: p, kind: 'expense', currencyMode: mode).total;
      return (i, e, i - e);
    }

    final (income, expense, net) = cash(period);
    final (assetT, assetU, missing) = assetsPnlTotal(s, period, todayS);
    final assetTotal = mode == 'USD' ? assetU : assetT;
    final start = formatJalaali(period.start), end = formatJalaali(period.end);
    final convertCount = groupConvertTransactions(s.transactions.where((t) => t.dateString.compareTo(start) >= 0 && t.dateString.compareTo(end) <= 0).toList()).length;

    List<CompareMetric>? cashMetrics, assetMetrics;
    String subtitle = '';
    if (scope != 'all') {
      final prev = matchingPriorPeriod(period);
      if (prev != null) {
        final (pi, pe, pn) = cash(prev);
        final (pt, pu, _) = assetsPnlTotal(s, prev, todayS);
        cashMetrics = [
          CompareMetric('income', 'درآمد', income, pi, true),
          CompareMetric('expense', 'هزینه', expense, pe, false),
          CompareMetric('net', 'مانده', net, pn, true),
        ];
        assetMetrics = [CompareMetric('pnl', 'سود/زیان کل', assetTotal, mode == 'USD' ? pu : pt, true)];
        subtitle = priorPeriodCompareLabel(period.kind);
      }
    }
    final scopeLabel = formatCurrentPeriodLabel(scope);

    Widget card({required IconData icon, required String title, required List<Widget> children, VoidCallback? onTap}) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AppCard(
            onTap: onTap,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(icon, size: 16, color: C.purple400),
                const SizedBox(width: 6),
                Expanded(child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: C.slate200))),
                if (onTap != null) const Icon(Icons.chevron_left, size: 18, color: C.slate500),
              ]),
              Text(scopeLabel, style: const TextStyle(fontSize: 11, color: C.slate500)),
              ...children,
            ]),
          ),
        );

    return SubPage(
      title: 'گزارش‌ها',
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
        Row(children: [
          for (final k in _scopes) ...[
            Expanded(child: FilterChipX(active: scope == k, label: formatCurrentPeriodLabel(k), onTap: () => setState(() => scope = k))),
            if (k != _scopes.last) const SizedBox(width: 8),
          ],
        ]),
        const SizedBox(height: 14),
        card(
          icon: Icons.account_balance_wallet_outlined,
          title: 'درآمد و هزینه',
          onTap: () => Nav.push(context, reportHref('cashflow', period)),
          children: [
            const SizedBox(height: 10),
            Money('${net >= 0 ? '+' : ''}${formatCurrency(net, mode)}', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: net >= 0 ? C.emerald400 : C.rose400)),
            const SizedBox(height: 4),
            Money('درآمد ${formatCurrency(income, mode)} · هزینه ${formatCurrency(expense, mode)}', style: const TextStyle(fontSize: 11, color: C.slate400)),
          ],
        ),
        card(
          icon: Icons.toll_outlined,
          title: 'سود/زیان دارایی‌ها',
          onTap: () => Nav.push(context, reportHref('assets', period)),
          children: [
            const SizedBox(height: 10),
            Row(children: [
              Icon(assetTotal >= 0 ? Icons.trending_up : Icons.trending_down, size: 18, color: assetTotal >= 0 ? C.emerald400 : C.rose400),
              const SizedBox(width: 6),
              Money('${assetTotal > 0 ? '+' : ''}${formatCurrency(assetTotal, mode)}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: assetTotal >= 0 ? C.emerald400 : C.rose400)),
            ]),
            if (missing > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('${toPersianDigits(missing)} دارایی بدون قیمت پایان دوره — جمع ناقص است.', style: const TextStyle(fontSize: 11, color: C.amber300)),
              ),
          ],
        ),
        if (cashMetrics != null) ...[
          PeriodComparisonCard(title: 'مقایسه جریان نقد', subtitle: subtitle, metrics: cashMetrics, currencyMode: mode),
          const SizedBox(height: 12),
          PeriodComparisonCard(title: 'مقایسه سود/زیان دارایی', subtitle: subtitle, metrics: assetMetrics!, currencyMode: mode),
          const SizedBox(height: 12),
        ],
        if (convertCount > 0)
          card(icon: Icons.toll_outlined, title: 'تبدیل دارایی', children: [
            const SizedBox(height: 8),
            Text(toPersianDigits(convertCount), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
            const Text('عملیات تبدیل ثبت‌شده', style: TextStyle(fontSize: 11, color: C.slate500)),
          ]),
      ]),
    );
  }
}
