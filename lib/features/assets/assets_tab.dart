// Port of AssetsTab.tsx + asset-list-filters.ts.

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
import '../goals/goal_progress_display.dart';

bool isZeroValueAsset(AssetStats s) {
  if (s.totalAmount > 1e-9) return s.currentValueToman <= 0.01 && s.currentValueUsd <= 0.01;
  return true;
}

class AssetGroup {
  final String id, name, color;
  final List<Asset> assets = [];
  AssetGroup(this.id, this.name, this.color);
}

List<AssetGroup> groupAssetsByCategory(List<Asset> assets, List<Category> categories) {
  final map = <String, AssetGroup>{};
  for (final c in categories.where((c) => c.kind == 'asset')) {
    map[c.id] = AssetGroup(c.id, c.name, c.color);
  }
  map['uncategorized'] = AssetGroup('uncategorized', 'بدون دسته‌بندی', '#64748b');
  for (final a in assets) {
    final id = a.categoryId ?? 'uncategorized';
    (map[id] ?? map['uncategorized']!).assets.add(a);
  }
  return map.values.where((g) => g.assets.isNotEmpty).toList();
}

class AssetsTab extends StatefulWidget {
  const AssetsTab({super.key});
  @override
  State<AssetsTab> createState() => _AssetsTabState();
}

class _AssetsTabState extends State<AssetsTab> {
  String viewMode = 'groups';
  String zeroFilter = 'hide';

  @override
  Widget build(BuildContext context) {
    final s = context.watch<PortfolioStore>();
    final mode = s.currencyMode;
    final todayS = todayStr();
    final pnl = {for (final a in s.assets) a.id: computeAssetPnl(a, s.transactions, s.dailyPrices, s.usdRate, todayS)};
    final stats = {for (final a in s.assets) a.id: calculateAssetStats(a, s.transactions, mode, s.usdRate)};
    final visible = zeroFilter == 'show' ? s.assets : s.assets.where((a) => !isZeroValueAsset(stats[a.id]!)).toList();
    final groups = groupAssetsByCategory(visible, s.categories);
    final flat = stableSorted(visible, (a, b) {
      final oa = a.orderIndex ?? 0, ob = b.orderIndex ?? 0;
      if (oa != ob) return oa - ob;
      return faCompare(a.name, b.name);
    });
    final snaps = buildAssetSnapshots(s.assets, s.transactions, mode, s.usdRate);
    final total = totalSnapshotValueToman(snaps);
    final goalsByAsset = <String, List<Goal>>{};
    for (final g in s.goals.where((g) => g.scope == 'asset')) {
      if (g.assetId != null) (goalsByAsset[g.assetId!] ??= []).add(g);
    }
    final groupGoal = <String, Goal>{};
    for (final g in s.goals.where((g) => g.scope == 'asset_group' && g.targetKind == 'allocation_percent')) {
      if (g.categoryId != null) groupGoal[g.categoryId!] = g;
    }
    final catColor = {for (final c in s.categories) c.id: c.color};

    Widget row(Asset a, String color) => _AssetRow(
          asset: a,
          groupColor: color,
          stats: stats[a.id]!,
          pnl: pnl[a.id],
          mode: mode,
          goals: goalsByAsset[a.id] ?? const [],
          snaps: snaps,
          total: total,
        );

    return RefreshIndicator(
      onRefresh: s.refreshAll,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
        Row(children: [
          const Expanded(child: Text('لیست دارایی‌ها', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white))),
          IconBtn(Icons.track_changes, tooltip: 'هدف‌ها', onTap: () => Nav.push(context, '/manage/goals')),
          const SizedBox(width: 8),
          IconBtn(Icons.trending_up, tooltip: 'قیمت‌ها و نرخ‌ها', onTap: () => Nav.push(context, '/prices')),
          const SizedBox(width: 8),
          IconBtn(Icons.tune, tooltip: 'مدیریت', onTap: () => Nav.push(context, '/manage/assets')),
        ]),
        const SizedBox(height: 14),
        if (s.isLoadingData && s.assets.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
        if (!s.isLoadingData && s.assets.isEmpty)
          EmptyState(icon: Icons.trending_up, title: 'هنوز دارایی‌ای نساخته‌ای.', actionLabel: 'افزودن دارایی', onAction: () => Nav.push(context, '/manage/assets')),
        if (s.assets.isNotEmpty && visible.isEmpty)
          EmptyState(icon: Icons.trending_up, title: 'دارایی با ارزش غیرصفر پیدا نشد.', actionLabel: 'نمایش دارایی‌های صفر', onAction: () => setState(() => zeroFilter = 'show')),
        if (s.assets.isNotEmpty && visible.isNotEmpty) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              FilterChipX(active: viewMode == 'groups', label: 'گروه‌ها', onTap: () => setState(() => viewMode = 'groups')),
              const SizedBox(width: 6),
              FilterChipX(active: viewMode == 'all', label: 'همه', onTap: () => setState(() => viewMode = 'all')),
              Container(width: 1, height: 18, margin: const EdgeInsets.symmetric(horizontal: 10), color: C.white10),
              FilterChipX(active: zeroFilter == 'hide', label: 'بدون صفر', onTap: () => setState(() => zeroFilter = 'hide')),
              const SizedBox(width: 6),
              FilterChipX(active: zeroFilter == 'show', label: 'شامل صفر', onTap: () => setState(() => zeroFilter = 'show')),
            ]),
          ),
          const SizedBox(height: 14),
          if (viewMode == 'groups')
            for (final g in groups) ...[
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 8),
                child: Row(children: [
                  Container(width: 4, height: 16, decoration: BoxDecoration(color: hexColor(g.color), borderRadius: BorderRadius.circular(4))),
                  const SizedBox(width: 8),
                  Text(g.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: C.slate200)),
                  const SizedBox(width: 12),
                  if (g.id != 'uncategorized' && groupGoal.containsKey(g.id))
                    Expanded(
                      child: GoalProgressDisplay(label: 'هدف گروه', kind: 'percent', compact: true, progress: calculateGroupGoalProgress(groupGoal[g.id]!, snaps, total)),
                    ),
                ]),
              ),
              for (final a in g.assets) row(a, g.color),
            ]
          else
            for (final a in flat) row(a, catColor[a.categoryId] ?? '#64748b'),
        ],
      ]),
    );
  }
}

class _AssetRow extends StatelessWidget {
  final Asset asset;
  final String groupColor;
  final AssetStats stats;
  final AssetPnl? pnl;
  final String mode;
  final List<Goal> goals;
  final List<AssetSnapshot> snaps;
  final double total;
  const _AssetRow({required this.asset, required this.groupColor, required this.stats, required this.pnl, required this.mode, required this.goals, required this.snaps, required this.total});

  @override
  Widget build(BuildContext context) {
    final p = pnl;
    final value = mode == 'USD' ? stats.currentValueUsd : stats.currentValueToman;
    final inPnl = p != null && p.included;
    final hasOpen = inPnl && p.holdings > 0 && p.activeAvailable && p.activeCost.toman > 0;
    final open = p?.activeValue.pick(mode) ?? 0;
    final openPct = p == null ? 0.0 : (pnlPercent(p.activeValue, p.activeCost, mode) ?? 0);
    final year = p?.yearValue.pick(mode) ?? 0;
    final all = p?.allTimeValue.pick(mode) ?? 0;
    final showYear = inPnl && !p.yearEmpty;
    final showAll = inPnl && p.allTimeInvested.pick(mode) > 0;
    final color = hexColor(groupColor, C.slate500);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        onTap: () => Nav.push(context, '/assets/${asset.id}'),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          EntityIcon(iconUrl: asset.iconUrl, fallback: Icons.show_chart, bgColor: color.withValues(alpha: 0.13), color: color, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(asset.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
              Text('${formatAssetAmount(stats.totalAmount, asset.decimalPlaces)} ${asset.unit}', style: const TextStyle(fontSize: 12, color: C.slate400)),
              if (asset.includeInBalance == false) const Text('خارج از ارزش کل سبد', style: TextStyle(fontSize: 10, color: C.amber300)),
              if (!asset.includeInProfitLoss) const Text('خارج از سود/زیان', style: TextStyle(fontSize: 10, color: C.slate500)),
              for (final g in goals.take(2))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: GoalProgressDisplay(
                    label: g.targetKind == 'quantity' ? 'هدف مقدار' : 'هدف درصد سبد',
                    kind: goalValueKindFromGoal(g.targetKind),
                    unit: asset.unit,
                    compact: true,
                    progress: calculateAssetGoalProgress(g, snaps, total),
                  ),
                ),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Money(formatCurrency(value, mode), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
            if (stats.totalAmount > 0 && stats.currentPriceSource == 'trade') const Text('با قیمت آخرین معامله', style: TextStyle(fontSize: 10, color: C.slate500)),
            if (hasOpen)
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: (open >= 0 ? C.emerald400 : C.rose400).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(999)),
                child: Money('${open >= 0 ? '+' : ''}${formatCurrency(open, mode)}  ${openPct >= 0 ? '+' : ''}${toFixed(openPct, 1)}%',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: open >= 0 ? C.emerald300 : C.rose300)),
              ),
            if (showYear)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('امسال${p.yearPartial ? '*' : ''} ', style: const TextStyle(fontSize: 10, color: C.slate500)),
                  Money('${year >= 0 ? '+' : ''}${formatCurrency(year, mode)}', style: TextStyle(fontSize: 10, color: (year >= 0 ? C.emerald400 : C.rose400).withValues(alpha: 0.8))),
                ]),
              ),
            if (showAll)
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('از ابتدا ', style: TextStyle(fontSize: 10, color: C.slate500)),
                Money('${all >= 0 ? '+' : ''}${formatCurrency(all, mode)}', style: TextStyle(fontSize: 10, color: (all >= 0 ? C.emerald400 : C.rose400).withValues(alpha: 0.8))),
              ]),
          ]),
        ]),
      ),
    );
  }
}
