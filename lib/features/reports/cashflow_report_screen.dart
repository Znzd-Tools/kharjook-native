// Port of CashflowReportView.tsx.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/files.dart';
import '../../core/store.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/toast.dart';
import '../../core/ui/widgets.dart';
import '../../core/utils/digits.dart';
import '../../core/utils/format.dart';
import '../../core/utils/period.dart';
import 'report_logic.dart';

class CashflowReportScreen extends StatefulWidget {
  final Map<String, String> query;
  const CashflowReportScreen({super.key, required this.query});
  @override
  State<CashflowReportScreen> createState() => _CashflowReportScreenState();
}

class _CashflowReportScreenState extends State<CashflowReportScreen> {
  late Period period = clampPeriodToToday(decodePeriodParams(widget.query['period'], widget.query['d']));
  late String tab = widget.query['tab'] == 'income' ? 'income' : 'expense';
  late String? walletId = (widget.query['wallet'] ?? '').isEmpty ? null : widget.query['wallet'];
  Set<String> expanded = {};

  void _patch(VoidCallback fn) => setState(() {
        fn();
        expanded = {};
      });

  @override
  Widget build(BuildContext context) {
    final s = context.watch<PortfolioStore>();
    final mode = s.currencyMode;
    final income = rollupCategories(transactions: s.transactions, categories: s.categories, period: period, kind: 'income', walletId: walletId, currencyMode: mode);
    final expense = rollupCategories(transactions: s.transactions, categories: s.categories, period: period, kind: 'expense', walletId: walletId, currencyMode: mode);
    final active = tab == 'income' ? income : expense;
    final accent = tab == 'income' ? C.emerald400 : C.rose400;
    final net = income.total - expense.total;

    Future<void> export() async {
      final walletLabel = walletId != null ? (s.wallets.where((w) => w.id == walletId).firstOrNull?.name ?? 'کیف پول') : 'همه کیف‌ها';
      try {
        await shareTextFile(cashflowCsvFilename(period), buildCashflowCsv(period: period, currencyMode: mode, walletLabel: walletLabel, income: income, expense: expense));
      } catch (_) {
        Toast.error('خطا در ساخت فایل خروجی.');
      }
    }

    // Hide rows whose ancestor is collapsed.
    final visible = <RollupNode>[];
    var skipDepth = -1;
    for (final n in active.nodes) {
      if (skipDepth != -1 && n.depth > skipDepth) continue;
      skipDepth = -1;
      visible.add(n);
      if (n.hasChildren && !expanded.contains(n.id)) skipDepth = n.depth;
    }

    Widget tabCard(String key, String label, IconData icon, double value, Color tone) {
      final on = tab == key;
      return Expanded(
        child: AppCard(
          padding: const EdgeInsets.all(12),
          color: on ? tone.withValues(alpha: 0.06) : null,
          borderColor: on ? tone.withValues(alpha: 0.4) : null,
          onTap: () => _patch(() => tab = key),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, size: 16, color: tone),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontSize: 12, color: C.slate400)),
            ]),
            const SizedBox(height: 4),
            Money(formatCurrency(value, mode), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: on ? tone : C.slate300)),
          ]),
        ),
      );
    }

    return SubPage(
      title: 'گزارش درآمد و هزینه',
      actions: [IconButton(tooltip: 'خروجی CSV', onPressed: export, icon: const Icon(Icons.download, size: 18))],
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
        PeriodNavHeader(period: period, onChange: (p) => _patch(() => period = clampPeriodToToday(p))),
        const SizedBox(height: 12),
        if (s.wallets.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              FilterChipX(active: walletId == null, label: 'همه کیف‌ها', onTap: () => _patch(() => walletId = null)),
              for (final w in s.wallets) ...[
                const SizedBox(width: 6),
                FilterChipX(active: walletId == w.id, label: w.name, onTap: () => _patch(() => walletId = w.id)),
              ],
            ]),
          ),
        const SizedBox(height: 12),
        Row(children: [
          tabCard('income', 'درآمد', Icons.arrow_circle_down_outlined, income.total, C.emerald400),
          const SizedBox(width: 10),
          tabCard('expense', 'هزینه', Icons.arrow_circle_up_outlined, expense.total, C.rose400),
        ]),
        const SizedBox(height: 12),
        AppCard(
          child: Column(children: [
            const Text('مانده دوره', style: TextStyle(fontSize: 12, color: C.slate400)),
            const SizedBox(height: 4),
            Money('${net >= 0 ? '+' : ''}${formatCurrency(net, mode)}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: net >= 0 ? C.emerald400 : C.rose400)),
            const SizedBox(height: 2),
            Money('درآمد ${formatCurrency(income.total, mode)} · هزینه ${formatCurrency(expense.total, mode)}', style: const TextStyle(fontSize: 11, color: C.slate500)),
          ]),
        ),
        const SizedBox(height: 12),
        if (active.nodes.isEmpty && active.uncategorizedTotal == 0)
          Padding(
            padding: const EdgeInsets.all(30),
            child: Column(children: [
              const Icon(Icons.folder_open, size: 28, color: C.slate600),
              const SizedBox(height: 8),
              Text('در این بازه، ${tab == 'income' ? 'درآمدی' : 'هزینه‌ای'} ثبت نشده.', style: const TextStyle(fontSize: 12, color: C.slate500)),
            ]),
          )
        else ...[
          for (final n in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Opacity(
                opacity: (n.depth == 0 ? n.rolled : n.own) == 0 ? 0.5 : 1,
                child: Material(
                  color: C.raised,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: n.hasChildren
                        ? () => setState(() => expanded.contains(n.id) ? expanded.remove(n.id) : expanded.add(n.id))
                        : null,
                    child: Padding(
                      padding: EdgeInsetsDirectional.fromSTEB(12.0 + n.depth * 16, 10, 12, 10),
                      child: Row(children: [
                        SizedBox(
                          width: 16,
                          child: n.hasChildren
                              ? AnimatedRotation(
                                  turns: expanded.contains(n.id) ? 0 : 0.25,
                                  duration: const Duration(milliseconds: 150),
                                  child: const Icon(Icons.expand_more, size: 14, color: C.slate400),
                                )
                              : null,
                        ),
                        const SizedBox(width: 6),
                        Dot(hexColor(n.color)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(n.name, style: const TextStyle(fontSize: 13, color: C.slate200))),
                        Money(formatCurrency(n.depth == 0 ? n.rolled : n.own, mode), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: accent)),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          if (active.uncategorizedTotal > 0)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: C.raised, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.white10)),
              child: Row(children: [
                const Icon(Icons.account_balance_wallet_outlined, size: 14, color: C.slate500),
                const SizedBox(width: 8),
                Expanded(child: Text('بدون دسته‌بندی (${active.uncategorizedCount})', style: const TextStyle(fontSize: 13, color: C.slate300))),
                Money(formatCurrency(active.uncategorizedTotal, mode), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: accent)),
              ]),
            ),
        ],
        if (active.unpricedCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: AppCard(
              padding: const EdgeInsets.all(12),
              color: C.amber.withValues(alpha: 0.08),
              borderColor: C.amber.withValues(alpha: 0.3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.error_outline, size: 14, color: C.amber300),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${toPersianDigits(active.unpricedCount)} تراکنش بدون قیمت لحظه‌ای ثبت شده و در جمع لحاظ نشده. ویرایش و ثبت قیمت تا سود/زیان دقیق محاسبه شود.',
                      style: const TextStyle(fontSize: 11, color: C.amber300, height: 1.6)),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}
