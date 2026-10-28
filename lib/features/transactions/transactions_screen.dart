// Port of TransactionsTab.tsx and export-transaction-csv.ts.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/router.dart';
import '../../core/logic/ledger.dart';
import '../../core/models.dart';
import '../../core/services/files.dart';
import '../../core/store.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/toast.dart';
import '../../core/ui/widgets.dart';
import '../../core/utils/digits.dart';
import '../../core/utils/jalali.dart';
import '../../core/utils/period.dart';
import 'history_widgets.dart';
import 'tx_logic.dart';

const _csvTypes = {'BUY': 'buy', 'SELL': 'sell', 'TRANSFER': 'transfer', 'INCOME': 'income', 'EXPENSE': 'expense'};

String _csvEscape(String v) => RegExp(r'[",\n]').hasMatch(v) ? '"${v.replaceAll('"', '""')}"' : v;

double? _primaryAmount(Transaction t) => switch (t.type) {
      'EXPENSE' || 'SELL' => t.sourceAmount ?? t.amount,
      'INCOME' || 'BUY' => t.targetAmount ?? t.amount,
      'TRANSFER' => t.sourceAmount ?? t.targetAmount ?? t.amount,
      _ => t.amount,
    };

String buildTransactionCsv(List<Transaction> txs, List<Wallet> wallets, List<Asset> assets, List<Category> categories) {
  final l = HistoryLookup(wallets, assets, categories);
  String or(String a, String b) => a.isNotEmpty ? a : b;
  final rows = stableSorted(txs, (a, b) => b.dateString.compareTo(a.dateString)).map((t) {
    final amount = _primaryAmount(t);
    return [
      t.dateString,
      _csvTypes[t.type] ?? t.type.toLowerCase(),
      amount != null ? jsNumStr(amount) : '',
      or(l.w(t.sourceWalletId), l.w(t.targetWalletId)),
      or(or(l.a(t.sourceAssetId), l.a(t.targetAssetId)), l.a(t.assetId)),
      l.c(t.categoryId),
      t.note ?? '',
      t.amountTomanAtTime != null ? jsNumStr(t.amountTomanAtTime!) : '',
      t.amountUsdAtTime != null ? jsNumStr(t.amountUsdAtTime!) : '',
    ].map(_csvEscape).join(',');
  });
  return ['date,type,amount,wallet,asset,category,note,amount_toman,amount_usd', ...rows].join('\n');
}

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});
  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  String query = '', typeFilter = 'ALL';
  late String dateFrom = formatJalaali(currentPeriod('month').start);
  late String dateTo = todayStr();

  bool _inRange(String d) {
    if (dateFrom.isEmpty && dateTo.isEmpty) return true;
    if (dateFrom.isNotEmpty && d.compareTo(dateFrom) < 0) return false;
    if (dateTo.isNotEmpty && d.compareTo(dateTo) > 0) return false;
    return true;
  }

  Future<void> _export(PortfolioStore s) async {
    try {
      await shareTextFile('transactions.csv', buildTransactionCsv(s.transactions, s.wallets, s.assets, s.categories));
    } catch (_) {
      Toast.error('خطا در ساخت فایل خروجی.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<PortfolioStore>();
    final lookup = HistoryLookup(s.wallets, s.assets, s.categories);
    final groups = groupConvertTransactions(s.transactions);
    final convertIds = transactionIdsInConvertGroups(s.transactions);
    final singles = s.transactions.where((t) {
      if (convertIds.contains(t.id)) return false;
      if (typeFilter != 'ALL' && t.type != typeFilter) return false;
      if (!_inRange(t.dateString)) return false;
      return transactionMatchesSearch(t, query, lookup);
    });
    final fGroups = groups.where((g) {
      if (typeFilter != 'ALL' && typeFilter != 'SELL' && typeFilter != 'BUY') return false;
      if (!_inRange(g.sell.dateString)) return false;
      final hay = '${g.sell.note ?? ''} ${g.buy.note ?? ''}';
      if (query.trim().isNotEmpty && !hay.contains(query.trim())) return false;
      return true;
    });
    final items = stableSorted(<(String, Transaction?, ConvertGroup?)>[
      for (final t in singles) (t.dateString, t, null),
      for (final g in fGroups) (g.sell.dateString, null, g),
    ], (a, b) => b.$1.compareTo(a.$1));

    if (s.isLoadingData && s.transactions.isEmpty) {
      return const SubPage(title: 'تراکنش‌ها', body: Center(child: CircularProgressIndicator()));
    }

    return SubPage(
      title: 'تراکنش‌ها',
      actions: [
        TextButton.icon(
          onPressed: s.transactions.isEmpty ? null : () => _export(s),
          icon: const Icon(Icons.download, size: 16),
          label: const Text('خروجی CSV'),
        ),
      ],
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
        if (!s.transactionsFullyLoaded)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Row(children: [
              SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 8),
              Text('در حال بارگذاری تاریخچه کامل...', style: TextStyle(fontSize: 12, color: C.slate500)),
            ]),
          ),
        HistorySearchBar(value: query, onChanged: (v) => setState(() => query = v)),
        const SizedBox(height: 10),
        TypeFilterChips(value: typeFilter, onChanged: (v) => setState(() => typeFilter = v)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: Field(label: 'از تاریخ', child: AppTextField(value: dateFrom, onChanged: (v) => setState(() => dateFrom = latinizeDigits(v)), hint: '1403/01/01', ltr: true))),
          const SizedBox(width: 10),
          Expanded(child: Field(label: 'تا تاریخ', child: AppTextField(value: dateTo, onChanged: (v) => setState(() => dateTo = latinizeDigits(v)), hint: '1403/12/29', ltr: true))),
        ]),
        if (items.isEmpty)
          EmptyState(
            icon: Icons.receipt_outlined,
            title: s.transactions.isEmpty ? 'هنوز تراکنشی ثبت نشده.' : 'تراکنشی با این فیلتر پیدا نشد.',
            actionLabel: s.transactions.isEmpty ? 'ثبت تراکنش' : null,
            onAction: s.transactions.isEmpty ? () => Nav.push(context, '/transactions/new') : null,
          )
        else
          for (final (_, tx, g) in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: g != null
                  ? ConvertCard(group: g, assets: s.assets, onEdit: () => Nav.push(context, '/transactions/${g.sell.id}/edit'))
                  : AppCard(
                      onTap: () => Nav.push(context, '/transactions/${tx.id}/edit'),
                      child: Row(children: [
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(kTxTypeLabels[tx!.type] ?? tx.type, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white)),
                          const SizedBox(height: 4),
                          Text(toPersianDigits(tx.dateString), style: const TextStyle(fontSize: 11, color: C.slate500)),
                        ]),
                        const SizedBox(width: 12),
                        Expanded(child: Text(tx.note?.isNotEmpty == true ? tx.note! : '—', textAlign: TextAlign.end, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: C.slate300))),
                      ]),
                    ),
            ),
      ]),
    );
  }
}
