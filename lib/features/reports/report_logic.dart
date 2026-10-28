// Ports of reports/utils/category-rollup.ts, export-cashflow-csv.ts,
// shared/utils/download-csv.ts, and the PeriodNavHeader /
// PeriodComparisonCard / ReportExportButton components.

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/widgets.dart';
import '../../core/utils/digits.dart';
import '../../core/utils/format.dart';
import '../../core/utils/jalali.dart';
import '../../core/utils/period.dart';
import '../transactions/tx_logic.dart' show jsNumStr;

// ─── CSV ────────────────────────────────────────────────────────────────────

String escapeCsvCell(Object? v) {
  if (v == null) return '';
  final s = v is num ? jsNumStr(v.toDouble()) : v.toString();
  if (RegExp(r'[",\n\r]').hasMatch(s)) return '"${s.replaceAll('"', '""')}"';
  return s;
}

String rowsToCsv(List<List<Object?>> rows) => rows.map((r) => r.map(escapeCsvCell).join(',')).join('\r\n');

String sanitizeCsvFilename(String part) {
  final s = part.replaceAll(RegExp(r'[^\w؀-ۿ.-]+'), '-').replaceAll(RegExp(r'-+'), '-');
  return s.length > 80 ? s.substring(0, 80) : s;
}

// ─── Category rollup ────────────────────────────────────────────────────────

class RollupNode {
  final String id, name, color;
  final int depth;
  final String? parentId;
  final bool hasChildren;
  final double own, rolled;
  final int txCount;
  RollupNode(this.id, this.name, this.color, this.depth, this.parentId, this.hasChildren, this.own, this.rolled, this.txCount);
}

class RollupResult {
  final List<RollupNode> nodes;
  final double total;
  final Map<String, List<String>> childrenOf;
  final double uncategorizedTotal;
  final int uncategorizedCount;
  final int unpricedCount;
  RollupResult(this.nodes, this.total, this.childrenOf, this.uncategorizedTotal, this.uncategorizedCount, this.unpricedCount);
}

Set<String> _reachableCategoryIds(List<Category> categories, String kind) {
  final scoped = categories.where((c) => c.kind == kind).toList();
  final ids = scoped.map((c) => c.id).toSet();
  final childrenOf = <String, List<String>>{};
  final roots = <String>[];
  for (final c in scoped) {
    if (c.parentId != null && ids.contains(c.parentId)) {
      (childrenOf[c.parentId!] ??= []).add(c.id);
    } else {
      roots.add(c.id);
    }
  }
  final out = <String>{};
  final stack = [...roots];
  while (stack.isNotEmpty) {
    final id = stack.removeLast();
    if (!out.add(id)) continue;
    stack.addAll(childrenOf[id] ?? const []);
  }
  return out;
}

RollupResult rollupCategories({
  required List<Transaction> transactions,
  required List<Category> categories,
  required Period period,
  required String kind,
  String? walletId,
  required String currencyMode,
}) {
  final reachable = _reachableCategoryIds(categories, kind);
  final ownAmount = <String, double>{}, ownCount = <String, int>{};
  double uncTotal = 0;
  int uncCount = 0, unpriced = 0;
  final targetType = kind == 'income' ? 'INCOME' : 'EXPENSE';

  for (final tx in transactions) {
    if (tx.type != targetType) continue;
    if (!isInPeriod(tx.dateString, period)) continue;
    final value = currencyMode == 'TOMAN' ? tx.amountTomanAtTime : tx.amountUsdAtTime;
    final txWallet = kind == 'income' ? tx.targetWalletId : tx.sourceWalletId;
    final txAsset = kind == 'income' ? tx.targetAssetId : tx.sourceAssetId;
    final isAsset = txWallet == null && txAsset != null;
    if (walletId != null) {
      if (isAsset) continue;
      if (txWallet != walletId) continue;
    }
    if (value == null || !value.isFinite || value <= 0) {
      if (value == null) unpriced++;
      continue;
    }
    final catId = tx.categoryId != null && reachable.contains(tx.categoryId) ? tx.categoryId : null;
    if (catId != null) {
      ownAmount[catId] = (ownAmount[catId] ?? 0) + value;
      ownCount[catId] = (ownCount[catId] ?? 0) + 1;
    } else {
      uncTotal += value;
      uncCount++;
    }
  }

  final scoped = categories.where((c) => c.kind == kind).toList();
  final scopedIds = scoped.map((c) => c.id).toSet();
  final childrenOf = <String, List<String>>{};
  final roots = <Category>[];
  for (final c in scoped) {
    if (!reachable.contains(c.id)) continue;
    if (c.parentId != null && scopedIds.contains(c.parentId)) {
      (childrenOf[c.parentId!] ??= []).add(c.id);
    } else {
      roots.add(c);
    }
  }

  final rolledById = <String, double>{};
  double visit(String id) {
    var sum = ownAmount[id] ?? 0;
    for (final cid in childrenOf[id] ?? const <String>[]) {
      sum += visit(cid);
    }
    rolledById[id] = sum;
    return sum;
  }

  for (final r in roots) {
    visit(r.id);
  }

  final byId = {for (final c in scoped) c.id: c};
  final nodes = <RollupNode>[];
  int cmp(String a, String b) {
    final ra = rolledById[a] ?? 0, rb = rolledById[b] ?? 0;
    if (rb != ra) return rb > ra ? 1 : -1;
    return faCompare(byId[a]?.name ?? '', byId[b]?.name ?? '');
  }

  void flat(String id, int depth) {
    final c = byId[id];
    if (c == null) return;
    final children = childrenOf[id] ?? const <String>[];
    nodes.add(RollupNode(id, c.name, c.color, depth, c.parentId != null && scopedIds.contains(c.parentId) ? c.parentId : null, children.isNotEmpty, ownAmount[id] ?? 0,
        rolledById[id] ?? 0, ownCount[id] ?? 0));
    for (final cid in stableSortedIds(children, cmp)) {
      flat(cid, depth + 1);
    }
  }

  for (final id in stableSortedIds(roots.map((r) => r.id).toList(), cmp)) {
    flat(id, 0);
  }

  var total = uncTotal;
  for (final r in roots) {
    total += rolledById[r.id] ?? 0;
  }
  return RollupResult(nodes, total, childrenOf, uncTotal, uncCount, unpriced);
}

List<String> stableSortedIds(List<String> ids, int Function(String, String) cmp) {
  final indexed = [for (var i = 0; i < ids.length; i++) (i, ids[i])];
  indexed.sort((a, b) {
    final c = cmp(a.$2, b.$2);
    return c != 0 ? c : a.$1 - b.$1;
  });
  return [for (final e in indexed) e.$2];
}

// ─── Cashflow CSV ───────────────────────────────────────────────────────────

void _appendRollupRows(List<List<Object?>> rows, String kindLabel, RollupResult r) {
  for (final n in r.nodes) {
    rows.add([kindLabel, n.depth, n.name, n.own, n.rolled, n.txCount]);
  }
  if (r.uncategorizedTotal > 0) {
    rows.add([kindLabel, 0, 'بدون دسته‌بندی', r.uncategorizedTotal, r.uncategorizedTotal, r.uncategorizedCount]);
  }
}

String buildCashflowCsv({required Period period, required String currencyMode, required String walletLabel, required RollupResult income, required RollupResult expense}) {
  final rows = <List<Object?>>[
    ['گزارش', 'درآمد و هزینه'],
    ['بازه', formatPeriodLabel(period)],
    ['از تاریخ', formatJalaali(period.start)],
    ['تا تاریخ', formatJalaali(period.end)],
    ['ارز', currencyMode == 'TOMAN' ? 'تومان' : 'دلار'],
    ['کیف پول', walletLabel],
    ['جمع درآمد', income.total],
    ['جمع هزینه', expense.total],
    ['مانده', income.total - expense.total],
    ['تراکنش بدون قیمت (درآمد)', income.unpricedCount],
    ['تراکنش بدون قیمت (هزینه)', expense.unpricedCount],
    [],
    ['نوع', 'سطح', 'دسته', 'مبلغ مستقیم', 'جمع با زیردسته', 'تعداد تراکنش'],
  ];
  _appendRollupRows(rows, 'درآمد', income);
  _appendRollupRows(rows, 'هزینه', expense);
  return rowsToCsv(rows);
}

String cashflowCsvFilename(Period p) => 'cashflow-${formatJalaali(p.start).replaceAll('/', '-')}-${formatJalaali(p.end).replaceAll('/', '-')}.csv';

// ─── Shared widgets ─────────────────────────────────────────────────────────

String reportHref(String type, Period p) {
  final (kind, d) = encodePeriodParams(p);
  return '/reports/$type?period=$kind&d=$d';
}

class PeriodNavHeader extends StatelessWidget {
  final Period period;
  final ValueChanged<Period> onChange;
  const PeriodNavHeader({super.key, required this.period, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final atCurrent = isCurrentPeriod(period);
    final isAll = period.kind == 'all';
    Widget arrow(IconData icon, int delta) => Material(
          color: C.raised,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: isAll ? null : () => onChange(shiftPeriod(period, delta)),
            child: SizedBox(width: 38, height: 38, child: Icon(icon, size: 18, color: isAll ? C.slate600 : C.slate300)),
          ),
        );
    return Column(children: [
      Segmented<String>(
        options: [for (final k in kPeriodKinds) (k, formatPeriodKindLabel(k))],
        value: period.kind,
        onChanged: (k) {
          if (k != period.kind) onChange(currentPeriod(k));
        },
      ),
      const SizedBox(height: 10),
      Row(children: [
        arrow(Icons.chevron_right, -1),
        Expanded(
          child: Column(children: [
            Text(formatPeriodLabel(period), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
            if (!atCurrent && !isAll)
              GestureDetector(
                onTap: () => onChange(currentPeriod(period.kind)),
                child: Text('برگشت به ${formatPeriodKindLabel(period.kind)} جاری', style: const TextStyle(fontSize: 11, color: C.purple400)),
              ),
            if (atCurrent && !isAll) Text('${formatPeriodKindLabel(period.kind)} جاری', style: const TextStyle(fontSize: 11, color: C.slate500)),
            if (isAll) const Text('نمایش تمام تاریخچه', style: TextStyle(fontSize: 11, color: C.slate500)),
          ]),
        ),
        arrow(Icons.chevron_left, 1),
      ]),
    ]);
  }
}

class CompareMetric {
  final String key, label;
  final double current, previous;
  final double? deltaPct;
  final bool higherIsBetter;
  CompareMetric(this.key, this.label, this.current, this.previous, this.higherIsBetter) : deltaPct = percentChange(current, previous);
}

class PeriodComparisonCard extends StatelessWidget {
  final String title, subtitle, currencyMode;
  final List<CompareMetric> metrics;
  const PeriodComparisonCard({super.key, required this.title, required this.subtitle, required this.metrics, required this.currencyMode});

  @override
  Widget build(BuildContext context) {
    if (metrics.isEmpty) return const SizedBox.shrink();
    String label(double? d) {
      if (d == null) return 'جدید';
      if (d == 0) return '۰٪';
      return '${d > 0 ? '+' : ''}${toPersianDigits(d.abs().toStringAsFixed(0))}٪';
    }

    Color tone(CompareMetric m) {
      final d = m.deltaPct;
      if (d == null || d == 0) return C.slate400;
      final improved = m.higherIsBetter ? d > 0 : d < 0;
      return improved ? C.emerald400 : C.rose400;
    }

    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
        Text(subtitle, style: const TextStyle(fontSize: 11, color: C.slate500)),
        const SizedBox(height: 8),
        for (final m in metrics)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m.label, style: const TextStyle(fontSize: 12, color: C.slate300)),
                  Money('${formatCurrency(m.current, currencyMode)}  ←  ${formatCurrency(m.previous, currencyMode)}', style: const TextStyle(fontSize: 11, color: C.slate500)),
                ]),
              ),
              Text(label(m.deltaPct), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tone(m))),
            ]),
          ),
      ]),
    );
  }
}
