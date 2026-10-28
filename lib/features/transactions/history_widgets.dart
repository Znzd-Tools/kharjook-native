// Ports of transaction-history-search.ts, TransactionHistorySearchBar,
// TransactionHistoryTypeFilter and ConvertTransactionCard.

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/widgets.dart';
import '../../core/utils/digits.dart';
import '../../core/utils/format.dart';
import 'tx_logic.dart';

const kTxTypeLabels = {'BUY': 'خرید', 'SELL': 'فروش', 'TRANSFER': 'انتقال', 'INCOME': 'درآمد', 'EXPENSE': 'هزینه'};

class HistoryLookup {
  final List<Wallet> wallets;
  final List<Asset> assets;
  final List<Category> categories;
  HistoryLookup(this.wallets, this.assets, this.categories);
  String w(String? id) => id == null ? '' : (wallets.where((x) => x.id == id).firstOrNull?.name ?? '');
  String a(String? id) => id == null ? '' : (assets.where((x) => x.id == id).firstOrNull?.name ?? '');
  String c(String? id) => id == null ? '' : (categories.where((x) => x.id == id).firstOrNull?.name ?? '');
}

String _norm(String q) => latinizeDigits(q.trim().toLowerCase());

void _amt(List<String> parts, double? v) {
  if (v == null || v.isNaN) return;
  parts.add(jsNumStr(v));
}

bool transactionMatchesSearch(Transaction tx, String query, HistoryLookup l) {
  final q = _norm(query);
  if (q.isEmpty) return true;
  final parts = [
    tx.dateString,
    tx.note ?? '',
    kTxTypeLabels[tx.type] ?? '',
    l.w(tx.sourceWalletId),
    l.w(tx.targetWalletId),
    l.a(tx.sourceAssetId),
    l.a(tx.targetAssetId),
    l.a(tx.assetId),
    l.c(tx.categoryId),
  ];
  _amt(parts, tx.sourceAmount);
  _amt(parts, tx.targetAmount);
  _amt(parts, tx.amount);
  _amt(parts, tx.priceToman);
  return _norm(parts.where((p) => p.isNotEmpty).join(' ')).contains(q);
}

bool convertGroupMatchesSearch(ConvertGroup g, String query, HistoryLookup l) {
  final q = _norm(query);
  if (q.isEmpty) return true;
  final parts = ['تبدیل', g.sell.dateString, g.sell.note ?? '', g.buy.note ?? '', l.a(g.sell.sourceAssetId), l.a(g.buy.targetAssetId), 'فروش', 'خرید'];
  _amt(parts, g.sell.sourceAmount ?? g.sell.amount);
  _amt(parts, g.buy.targetAmount ?? g.buy.amount);
  _amt(parts, g.sell.priceToman);
  _amt(parts, g.buy.priceToman);
  return _norm(parts.where((p) => p.isNotEmpty).join(' ')).contains(q);
}

List<ConvertGroup> convertGroupsForAsset(String id, List<ConvertGroup> gs) => gs.where((g) => g.sell.sourceAssetId == id || g.buy.targetAssetId == id).toList();
List<ConvertGroup> convertGroupsForWallet(String id, List<ConvertGroup> gs) => gs.where((g) => g.sell.targetWalletId == id || g.buy.sourceWalletId == id).toList();
List<ConvertGroup> convertGroupsTouchingTransactions(List<Transaction> txs, List<ConvertGroup> gs) {
  final ids = txs.map((t) => t.id).toSet();
  return gs.where((g) => ids.contains(g.sell.id) || ids.contains(g.buy.id)).toList();
}

class HistorySearchBar extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const HistorySearchBar({super.key, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => AppTextField(
        value: value,
        onChanged: onChanged,
        hint: 'جستجو در یادداشت، دسته، مبلغ...',
        prefixIcon: value.trim().isEmpty
            ? const Icon(Icons.search, size: 18, color: C.slate500)
            : IconButton(icon: const Icon(Icons.close, size: 16, color: C.slate400), onPressed: () => onChanged('')),
      );
}

class TypeFilterChips extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const TypeFilterChips({super.key, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          FilterChipX(active: value == 'ALL', label: 'همه', onTap: () => onChanged('ALL')),
          for (final t in ['BUY', 'SELL', 'TRANSFER', 'INCOME', 'EXPENSE']) ...[
            const SizedBox(width: 6),
            FilterChipX(active: value == t, label: kTxTypeLabels[t]!, onTap: () => onChanged(t)),
          ],
        ]),
      );
}

class ConvertCard extends StatelessWidget {
  final ConvertGroup group;
  final List<Asset> assets;
  final VoidCallback? onEdit, onDelete;
  const ConvertCard({super.key, required this.group, required this.assets, this.onEdit, this.onDelete});
  @override
  Widget build(BuildContext context) {
    final sa = findAsset(assets, group.sell.sourceAssetId);
    final ta = findAsset(assets, group.buy.targetAssetId);
    final sq = group.sell.sourceAmount ?? group.sell.amount ?? 0;
    final bq = group.buy.targetAmount ?? group.buy.amount ?? 0;
    final sp = group.sell.priceToman ?? 0, bp = group.buy.priceToman ?? 0;
    Widget side(String label, Asset? a, double q, double p, Color c) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: c.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(fontSize: 10, color: c)),
              Money(a != null ? '${formatAssetAmount(q, a.decimalPlaces)} ${a.unit}' : jsNumStr(q), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: C.slate200)),
              if (p > 0) Money('@ ${formatCurrency(p, 'TOMAN')}', style: const TextStyle(fontSize: 10, color: C.slate500)),
            ]),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        borderColor: const Color(0x4D8B5CF6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.swap_horiz, size: 15, color: Color(0xFFA78BFA)),
            const SizedBox(width: 6),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('تبدیل: ${sa?.name ?? 'دارایی'} → ${ta?.name ?? 'دارایی'}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                Text(latinizeDigits(group.sell.dateString), style: const TextStyle(fontSize: 11, color: C.slate500)),
              ]),
            ),
            if (onEdit != null) IconButton(icon: const Icon(Icons.edit_outlined, size: 17, color: C.slate400), onPressed: onEdit),
            if (onDelete != null) IconButton(icon: const Icon(Icons.delete_outline, size: 17, color: C.rose300), onPressed: onDelete),
          ]),
          const SizedBox(height: 8),
          Row(children: [side('فروش', sa, sq, sp, C.amber300), const SizedBox(width: 8), side('خرید', ta, bq, bp, C.purple300)]),
        ]),
      ),
    );
  }
}
