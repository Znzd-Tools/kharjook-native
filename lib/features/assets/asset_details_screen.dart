// Port of AssetDetailsView.tsx + AssetPnlBreakdown.tsx.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/router.dart';
import '../../core/logic/domain_utils.dart';
import '../../core/logic/ledger.dart';
import '../../core/logic/pnl.dart';
import '../../core/models.dart';
import '../../core/store.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/toast.dart';
import '../../core/ui/widgets.dart';
import '../../core/utils/digits.dart';
import '../../core/utils/format.dart';
import '../../core/utils/jalali.dart';
import '../goals/goal_progress_display.dart';
import '../transactions/history_widgets.dart';
import '../transactions/tx_logic.dart';

class AssetDetailsScreen extends StatefulWidget {
  final String assetId;
  const AssetDetailsScreen({super.key, required this.assetId});
  @override
  State<AssetDetailsScreen> createState() => _AssetDetailsScreenState();
}

class _AssetDetailsScreenState extends State<AssetDetailsScreen> {
  String typeFilter = 'ALL';
  String query = '';

  Future<void> _deleteTx(String id) async {
    if (!await confirmDialog(context, message: 'آیا از حذف این تراکنش مطمئن هستید؟', danger: true, confirmLabel: 'حذف')) return;
    try {
      await Supabase.instance.client.from('transactions').delete().eq('id', id);
      if (!mounted) return;
      context.read<PortfolioStore>().update((s) => s.transactions = s.transactions.where((t) => t.id != id).toList());
    } catch (_) {
      Toast.error('خطا در حذف رکورد.');
    }
  }

  Future<void> _deleteConvert(ConvertGroup g) async {
    if (!await confirmDialog(context, message: 'آیا از حذف این تبدیل (فروش + خرید) مطمئن هستید؟', danger: true, confirmLabel: 'حذف')) return;
    try {
      await Supabase.instance.client.from('transactions').delete().inFilter('id', [g.sell.id, g.buy.id]);
      if (!mounted) return;
      context.read<PortfolioStore>().update((s) => s.transactions = s.transactions.where((t) => t.id != g.sell.id && t.id != g.buy.id).toList());
    } catch (_) {
      Toast.error('خطا در حذف تبدیل.');
    }
  }

  void _openConvert(Asset a, {String? targetAmount}) {
    final q = {'type': kConvertMode, 'assetId': a.id, if (targetAmount != null) 'targetAssetId': a.id, if (targetAmount != null) 'targetAmount': targetAmount};
    Nav.push(context, Uri(path: '/transactions/new', queryParameters: q).toString());
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<PortfolioStore>();
    final asset = findAsset(s.assets, widget.assetId);
    if (asset == null) {
      return const SubPage(title: 'دارایی', body: Center(child: Text('دارایی پیدا نشد.', style: TextStyle(color: C.slate400))));
    }
    final mode = s.currencyMode;
    final usdRate = s.usdRate;
    final todayS = todayStr();
    final stats = calculateAssetStats(asset, s.transactions, mode, usdRate);
    final pnl = computeAssetPnl(asset, s.transactions, s.dailyPrices, usdRate, todayS);
    final dp = asset.decimalPlaces;
    final touching = sortTransactionsNewestFirst(
        s.transactions.where((t) => t.assetId == asset.id || t.sourceAssetId == asset.id || t.targetAssetId == asset.id).toList());
    final visibleTxs = typeFilter == 'ALL' ? touching : touching.where((t) => t.type == typeFilter).toList();
    final groups = convertGroupsForAsset(asset.id, groupConvertTransactions(s.transactions));
    final convertIds = transactionIdsInConvertGroups(s.transactions);
    final lookup = HistoryLookup(s.wallets, s.assets, s.categories);
    final items = <(String, ConvertGroup?, Transaction?)>[];
    for (final g in groups) {
      if (typeFilter != 'ALL') {
        final ok = (typeFilter == 'SELL' && g.sell.sourceAssetId == asset.id) || (typeFilter == 'BUY' && g.buy.targetAssetId == asset.id);
        if (!ok) continue;
      }
      if (!convertGroupMatchesSearch(g, query, lookup)) continue;
      items.add((g.sell.dateString, g, null));
    }
    for (final t in visibleTxs) {
      if (convertIds.contains(t.id)) continue;
      if (!transactionMatchesSearch(t, query, lookup)) continue;
      items.add((t.dateString, null, t));
    }
    final sortedItems = stableSorted(items, (a, b) => b.$1.compareTo(a.$1));

    final snaps = buildAssetSnapshots(s.assets, s.transactions, mode, usdRate);
    final total = totalSnapshotValueToman(snaps);
    final goals = s.goals.where((g) => g.scope == 'asset' && g.assetId == asset.id).toList();
    AssetSnapshot? snap;
    for (final x in snaps) {
      if (x.asset.id == asset.id) snap = x;
    }
    final suggestions = <(String, String, String?)>[];
    for (final g in goals) {
      final p = calculateAssetGoalProgress(g, snaps, total);
      if (p == null) continue;
      final kind = goalValueKindFromGoal(g.targetKind);
      final sug = buildGoalActionSuggestion(GoalActionInput(
        name: asset.name,
        kind: kind,
        current: p.current,
        target: p.target,
        unit: asset.unit,
        decimalPlaces: asset.decimalPlaces,
        currentValueToman: snap?.valueToman ?? 0,
        portfolioValueToman: total,
        priceToman: asset.priceToman,
        currencyMode: mode,
        usdRate: usdRate,
        maxQuantity: snap?.quantity ?? 0,
        allowSell: true,
      ));
      if (sug == null) continue;
      final convertTarget = sug.$1 == 'buy' && kind == 'quantity' && p.remaining > 0 ? jsNumStr(p.remaining) : null;
      suggestions.add((sug.$1, sug.$2, convertTarget));
    }

    final value = mode == 'USD' ? stats.currentValueUsd : stats.currentValueToman;
    final headerHasOpen = pnl.included && pnl.holdings > 0 && pnl.activeAvailable;
    final headerOpen = pnl.activeValue.pick(mode);
    final headerPct = pnlPercent(pnl.activeValue, pnl.activeCost, mode);
    final profit = headerOpen >= 0;
    final pnlExcluded = !asset.includeInProfitLoss;
    final balanceExcluded = asset.includeInBalance == false;

    return SubPage(
      title: asset.name,
      bottom: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(children: [
            Expanded(child: AppButton('تبدیل این دارایی', icon: Icons.swap_horiz, variant: BtnVariant.secondary, expand: true, onPressed: () => _openConvert(asset))),
            const SizedBox(width: 10),
            Expanded(child: AppButton('ثبت عملیات جدید', icon: Icons.add, expand: true, onPressed: () => Nav.push(context, '/transactions/new?assetId=${asset.id}'))),
          ]),
        ),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        AppCard(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            EntityIcon(iconUrl: asset.iconUrl, fallback: Icons.show_chart, bgColor: const Color(0x1FA855F7), color: C.purple400, size: 52),
            const SizedBox(height: 10),
            const Text('ارزش فعلی کل', style: TextStyle(fontSize: 12, color: C.slate400)),
            Money(formatCurrency(value, mode), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white)),
            if (stats.totalAmount > 0 && stats.currentPriceSource == 'trade')
              Text('قیمت روز ثبت نشده؛ با قیمت آخرین معامله${stats.currentPriceDate != null ? ' (${toPersianDigits(stats.currentPriceDate!)})' : ''} حساب شد.',
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: C.amber300)),
            if (headerHasOpen) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: (profit ? C.emerald400 : C.rose400).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(999)),
                child: Money(
                  '${profit ? '+' : ''}${formatCurrency(headerOpen, mode)}${headerPct != null ? '  ${headerPct >= 0 ? '+' : ''}${toFixed(headerPct, 2)}%' : ''}',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: profit ? C.emerald300 : C.rose300),
                ),
              ),
              const Text('سود/زیان باز', style: TextStyle(fontSize: 10, color: C.slate500)),
            ],
            if (balanceExcluded)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('این دارایی در «ارزش کل سبد» و پراکندگی داشبورد لحاظ نمی‌شود؛ ارزش نمایش‌داده‌شده همان ارزش بازاری این دارایی است.',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: C.amber300, height: 1.6)),
              ),
            if (pnlExcluded && !balanceExcluded)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('این دارایی از محاسبات سود/زیان مستثنا شده و در ارزش کل سبد لحاظ می‌شود.', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: C.slate400, height: 1.6)),
              ),
            if (pnlExcluded && balanceExcluded)
              const Text('این دارایی از محاسبات سود/زیان هم مستثنا شده است.', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: C.slate400)),
          ]),
        ),
        if (pnl.included) ...[const SizedBox(height: 12), AssetPnlBreakdown(pnl: pnl, mode: mode)],
        if (goals.isNotEmpty) ...[
          const SizedBox(height: 12),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SectionTitle('پیشرفت هدف', icon: Icons.track_changes),
              for (final g in goals)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: GoalProgressDisplay(
                    label: g.targetKind == 'quantity' ? 'هدف مقداری' : 'هدف درصد سبد',
                    kind: goalValueKindFromGoal(g.targetKind),
                    unit: asset.unit,
                    progress: calculateAssetGoalProgress(g, snaps, total),
                  ),
                ),
              if (suggestions.isNotEmpty) ...[
                const Text('پیشنهاد', style: TextStyle(fontSize: 11, color: C.slate500)),
                for (final sg in suggestions)
                  sg.$1 == 'buy' && sg.$3 != null
                      ? TextButton(
                          onPressed: () => _openConvert(asset, targetAmount: sg.$3),
                          child: Align(alignment: AlignmentDirectional.centerStart, child: Text(sg.$2, style: const TextStyle(fontSize: 11, color: C.emerald300, decoration: TextDecoration.underline))),
                        )
                      : Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(sg.$2, style: TextStyle(fontSize: 11, color: sg.$1 == 'buy' ? C.emerald300 : C.rose300)),
                        ),
              ],
            ]),
          ),
        ],
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 2.4,
          children: [
            StatPill(label: 'موجودی', value: '${formatAssetAmount(stats.totalAmount, dp)} ${asset.unit}'),
            StatPill(label: 'میانگین خرید', value: formatCurrency(mode == 'USD' ? stats.avgBuyPriceUsd : stats.avgBuyPriceToman, mode)),
            StatPill(label: 'ارزش خرید کل', value: formatCurrency(mode == 'USD' ? stats.totalCostUsd : stats.totalCostToman, mode)),
            StatPill(label: 'قیمت روز', value: formatCurrency(mode == 'USD' ? stats.currentPriceUsd : stats.currentPriceToman, mode)),
          ],
        ),
        const SizedBox(height: 18),
        const Text('تاریخچه عملیات', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
        const SizedBox(height: 10),
        if (touching.isNotEmpty) ...[
          HistorySearchBar(value: query, onChanged: (v) => setState(() => query = v)),
          const SizedBox(height: 8),
          TypeFilterChips(value: typeFilter, onChanged: (v) => setState(() => typeFilter = v)),
          const SizedBox(height: 12),
        ],
        if (touching.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('تراکنشی ثبت نشده است.', textAlign: TextAlign.center, style: TextStyle(color: C.slate500, fontSize: 12))),
        if (touching.isNotEmpty && sortedItems.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(query.trim().isNotEmpty ? 'تراکنشی با این جستجو پیدا نشد.' : 'تراکنشی با این نوع وجود ندارد.', textAlign: TextAlign.center, style: const TextStyle(color: C.slate500, fontSize: 12)),
          ),
        for (final it in sortedItems)
          if (it.$2 != null)
            ConvertCard(group: it.$2!, assets: s.assets, onEdit: () => Nav.push(context, '/transactions/${it.$2!.sell.id}/edit'), onDelete: () => _deleteConvert(it.$2!))
          else
            _AssetTxRow(tx: it.$3!, asset: asset, categories: s.categories, onEdit: () => Nav.push(context, '/transactions/${it.$3!.id}/edit'), onDelete: () => _deleteTx(it.$3!.id)),
      ]),
    );
  }
}

class _AssetTxRow extends StatelessWidget {
  final Transaction tx;
  final Asset asset;
  final List<Category> categories;
  final VoidCallback onEdit, onDelete;
  const _AssetTxRow({required this.tx, required this.asset, required this.categories, required this.onEdit, required this.onDelete});
  @override
  Widget build(BuildContext context) {
    final cat = (tx.type == 'INCOME' || tx.type == 'EXPENSE') && tx.categoryId != null ? categories.where((c) => c.id == tx.categoryId).firstOrNull?.name : null;
    final acquire = tx.type == 'BUY' || tx.type == 'INCOME' || (tx.type == 'TRANSFER' && tx.targetAssetId == asset.id);
    final amount = tx.amount ?? (tx.type == 'BUY' || tx.type == 'INCOME' ? tx.targetAmount : tx.sourceAmount);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(color: C.raised, border: Border(left: BorderSide(color: acquire ? C.emerald : C.rose, width: 4))),
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(kTxTypeLabels[tx.type] ?? tx.type, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: acquire ? C.emerald300 : C.rose300)),
                  if (cat != null) Text(cat, style: const TextStyle(fontSize: 11, color: C.slate400)),
                  Text(latinizeDigits(tx.dateString), style: const TextStyle(fontSize: 11, color: C.slate500)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Money('${formatAssetAmount(amount, asset.decimalPlaces)} ${asset.unit}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                Money(formatCurrency(tx.priceToman, 'TOMAN'), style: const TextStyle(fontSize: 11, color: C.slate400)),
              ]),
            ]),
            const Divider(height: 18),
            Row(children: [
              Money('دلار: ${formatCurrency(tx.usdRate, 'TOMAN')}', style: const TextStyle(fontSize: 11, color: C.slate500)),
              const Spacer(),
              IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.edit_outlined, size: 17, color: C.slate400), onPressed: onEdit),
              IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.delete_outline, size: 17, color: C.rose300), onPressed: onDelete),
            ]),
          ]),
        ),
      ),
    );
  }
}

class AssetPnlBreakdown extends StatelessWidget {
  final AssetPnl pnl;
  final String mode;
  const AssetPnlBreakdown({super.key, required this.pnl, required this.mode});

  String _signed(double v) => '${v >= 0 ? '+' : ''}${formatCurrency(v, mode)}';
  Color _tone(double v) => v >= 0 ? C.emerald300 : C.rose300;

  Widget _row(String title, String hint, PnlPart? value, double? percent, List<(String, PnlPart)> splits, {bool emphasis = false, String? note}) {
    final v = value?.pick(mode);
    final accent = v != null && v < 0 ? C.rose : C.emerald;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: emphasis ? Color.alphaBlend(accent.withValues(alpha: 0.08), C.raised) : C.raised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: emphasis ? accent.withValues(alpha: 0.25) : C.borderSoft),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: emphasis ? C.slate200 : C.slate400)),
              Text(hint, style: const TextStyle(fontSize: 10, color: C.slate500, height: 1.5)),
            ]),
          ),
          if (v == null)
            const Text('—', style: TextStyle(color: C.slate500))
          else
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Money(_signed(v), style: TextStyle(fontSize: emphasis ? 19 : 14, fontWeight: FontWeight.w800, color: _tone(v))),
              if (percent != null) Money('${percent >= 0 ? '+' : ''}${toFixed(percent, 2)}%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _tone(v).withValues(alpha: 0.8))),
            ]),
        ]),
        if (splits.isNotEmpty && v != null) ...[
          const SizedBox(height: 10),
          Row(children: [
            for (final sp in splits)
              Expanded(
                child: Container(
                  margin: const EdgeInsetsDirectional.only(end: 6),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(sp.$1, style: const TextStyle(fontSize: 10, color: C.slate500)),
                    Money(_signed(sp.$2.pick(mode)), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _tone(sp.$2.pick(mode)).withValues(alpha: 0.85))),
                  ]),
                ),
              ),
          ]),
        ],
        if (note != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(note, style: const TextStyle(fontSize: 10, color: C.amber300))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final has = pnl.holdings > 0;
    final since = pnl.activeSince != null ? toPersianDigits(pnl.activeSince!) : null;
    return Column(children: [
      _row(
        'سود/زیان باز (فعال)',
        has ? 'روی واحدهایی که الان داری${since != null ? ' · از $since' : ''}' : 'الان واحدی نداری',
        has && pnl.activeAvailable ? pnl.activeValue : (has ? null : PnlPart.zero),
        has ? pnlPercent(pnl.activeValue, pnl.activeCost, mode) : null,
        has
            ? [
                ('سرمایه‌ی این موقعیت', pnl.activeCost),
                ('ارزش فعلی', PnlPart(pnl.activeCost.toman + pnl.activeValue.toman, pnl.activeCost.usd + pnl.activeValue.usd)),
              ]
            : const [],
        emphasis: true,
        note: has && !pnl.activeAvailable ? 'قیمتی برای این دارایی ثبت نشده.' : null,
      ),
      _row('سود/زیان امسال', 'از ۱ فروردین تا امروز · موجودی اول سال با قیمت پایان سال قبل', pnl.yearEmpty ? PnlPart.zero : pnl.yearValue,
          pnlPercent(pnl.yearValue, pnl.yearBase, mode), [('محقق‌شده امسال', pnl.yearRealized), ('باز امسال', pnl.yearOpen)],
          note: pnl.yearPartial ? 'قیمت اول یا آخر سال پیدا نشد؛ این عدد کامل نیست.' : null),
      _row('سود/زیان از ابتدا', 'همه‌ی خریدها و فروش‌ها + ارزش فعلی', pnl.allTimeValue, pnlPercent(pnl.allTimeValue, pnl.allTimeInvested, mode),
          [('محقق‌شده', pnl.allTimeRealized), ('باز', pnl.allTimeOpen)]),
    ]);
  }
}
