// Ports of AssetsReportView.tsx and export-assets-csv.ts.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/logic/ledger.dart';
import '../../core/logic/pnl.dart';
import '../../core/models.dart';
import '../../core/services/files.dart';
import '../../core/store.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/toast.dart';
import '../../core/ui/widgets.dart';
import '../../core/utils/digits.dart';
import '../../core/utils/format.dart';
import '../../core/utils/jalali.dart';
import '../../core/utils/period.dart';
import '../assets/assets_tab.dart' show isZeroValueAsset;
import 'report_logic.dart';

class _Totals {
  double realizedToman = 0, realizedUsd = 0, unrealizedToman = 0, unrealizedUsd = 0;
  int missing = 0, invalid = 0, oversell = 0, buys = 0, sells = 0;
}

String buildAssetsCsv(Period period, String mode, List<(Asset, AssetPeriodStats)> rows, _Totals t) {
  final usd = mode == 'USD';
  final out = <List<Object?>>[
    ['گزارش', 'سود/زیان دارایی‌ها'],
    ['بازه', formatPeriodLabel(period)],
    ['از تاریخ', formatJalaali(period.start)],
    ['تا تاریخ', formatJalaali(period.end)],
    ['ارز', mode == 'TOMAN' ? 'تومان' : 'دلار'],
    ['سود/زیان کل', usd ? t.realizedUsd + t.unrealizedUsd : t.realizedToman + t.unrealizedToman],
    ['محقق‌شده', usd ? t.realizedUsd : t.realizedToman],
    ['باز', usd ? t.unrealizedUsd : t.unrealizedToman],
    ['دارایی بدون قیمت پایان دوره', t.missing],
    ['تعداد خرید', t.buys],
    ['تعداد فروش', t.sells],
    [],
    [
      'دارایی', 'واحد', 'موجودی پایان دوره', 'سود/زیان محقق‌شده (تومان)', 'سود/زیان محقق‌شده (دلار)', 'سود/زیان باز (تومان)', 'سود/زیان باز (دلار)', //
      'سود/زیان کل (تومان)', 'سود/زیان کل (دلار)', 'تعداد خرید', 'تعداد فروش', 'میانگین خرید دوره (تومان)', 'میانگین فروش دوره (تومان)', 'قیمت پایان دوره (تومان)', 'قیمت پایان دوره موجود',
    ],
  ];
  for (final (a, s) in rows) {
    final av = s.periodUnrealizedAvailable;
    out.add([
      a.name, a.unit, s.endHoldings, s.realizedToman, s.realizedUsd, av ? s.periodUnrealizedToman : '', av ? s.periodUnrealizedUsd : '', //
      av ? s.realizedToman + s.periodUnrealizedToman : s.realizedToman, av ? s.realizedUsd + s.periodUnrealizedUsd : s.realizedUsd,
      s.bought.count, s.sold.count, s.bought.avgPriceToman, s.sold.avgPriceToman, s.periodEndPriceToman, av ? 'بله' : 'خیر',
    ]);
  }
  return rowsToCsv(out);
}

String assetsCsvFilename(Period p) => 'assets-pnl-${formatJalaali(p.start).replaceAll('/', '-')}-${formatJalaali(p.end).replaceAll('/', '-')}.csv';

Color _pnlColor(double v, [Color zero = C.slate300]) => v == 0 ? zero : (v > 0 ? C.emerald400 : C.rose400);
String _signed(double v, String mode) => '${v > 0 ? '+' : ''}${formatCurrency(v, mode)}';
String _fa(int n) => toPersianDigits(n);

class AssetsReportScreen extends StatefulWidget {
  final Map<String, String> query;
  const AssetsReportScreen({super.key, required this.query});
  @override
  State<AssetsReportScreen> createState() => _AssetsReportScreenState();
}

class _AssetsReportScreenState extends State<AssetsReportScreen> {
  late Period period = clampPeriodToToday(decodePeriodParams(widget.query['period'], widget.query['d']));
  late String? assetFilter = (widget.query['asset'] ?? '').isEmpty ? null : widget.query['asset'];
  late String zeros = widget.query['zeros'] == 'show' ? 'show' : 'hide';
  bool summaryOpen = false;
  final Set<String> openRows = {};

  @override
  Widget build(BuildContext context) {
    final s = context.watch<PortfolioStore>();
    final mode = s.currencyMode;
    final todayS = todayStr();

    var listAssets = zeros == 'show' ? s.assets : s.assets.where((a) => !isZeroValueAsset(calculateAssetStats(a, s.transactions, mode, s.usdRate))).toList();
    if (assetFilter != null && !listAssets.any((a) => a.id == assetFilter)) {
      final sel = s.assets.where((a) => a.id == assetFilter).firstOrNull;
      if (sel != null) listAssets = [...listAssets, sel];
    }
    final listIds = listAssets.map((a) => a.id).toSet();
    final endStr = formatJalaali(period.end);
    final all = [
      for (final a in s.assets.where((a) => a.includeInProfitLoss && listIds.contains(a.id)))
        (
          a,
          calculateAssetPeriodStats(
            a,
            s.transactions,
            period,
            s.usdRate,
            effectivePriceAt(a, endStr, s.dailyPrices, todayS, s.transactions),
            period.kind == 'all' ? null : effectiveOpeningPriceAt(a, period.start, s.dailyPrices, todayS, s.transactions),
          ),
        ),
    ];
    final visible = assetFilter != null ? all.where((x) => x.$1.id == assetFilter).toList() : all;
    final sorted = stableSorted(visible, (x, y) {
      final a = x.$2, b = y.$2;
      final aa = a.hadActivity ? 1 : 0, ba = b.hadActivity ? 1 : 0;
      if (aa != ba) return ba - aa;
      double d;
      if (a.hadActivity) {
        d = b.realizedToman.abs() - a.realizedToman.abs();
      } else {
        d = b.endHoldings * (b.periodEndPriceToman ?? y.$1.priceToman) - a.endHoldings * (a.periodEndPriceToman ?? x.$1.priceToman);
      }
      return d > 0 ? 1 : (d < 0 ? -1 : 0);
    });

    final t = _Totals();
    for (final (_, st) in visible) {
      t.realizedToman += st.realizedToman;
      t.realizedUsd += st.realizedUsd;
      if (st.periodUnrealizedAvailable) {
        t.unrealizedToman += st.periodUnrealizedToman;
        t.unrealizedUsd += st.periodUnrealizedUsd;
      } else if (st.currentHoldings > 0 || st.endHoldings > 0) {
        t.missing++;
      }
      t.invalid += st.invalidTradeCount;
      t.oversell += st.oversellCount;
      t.buys += st.bought.count;
      t.sells += st.sold.count;
    }
    final periodEndLabel = isCurrentPeriod(period) ? 'تا اکنون' : 'پایان ${formatPeriodLabel(period)}';

    Future<void> export() async {
      try {
        await shareTextFile(assetsCsvFilename(period), buildAssetsCsv(period, mode, sorted, t));
      } catch (_) {
        Toast.error('خطا در ساخت فایل خروجی.');
      }
    }

    String issues(int invalid, int oversell, String oversellLabel) =>
        [if (invalid > 0) '${_fa(invalid)} رکورد نامعتبر', if (oversell > 0) '${_fa(oversell)} $oversellLabel'].join(' · ');

    return SubPage(
      title: 'گزارش سود/زیان دارایی‌ها',
      actions: [IconButton(tooltip: 'خروجی CSV', onPressed: sorted.isEmpty ? null : export, icon: const Icon(Icons.download, size: 18))],
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
        PeriodNavHeader(period: period, onChange: (p) => setState(() => period = clampPeriodToToday(p))),
        const SizedBox(height: 12),
        if (listAssets.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              FilterChipX(active: assetFilter == null, label: 'همه دارایی‌ها', onTap: () => setState(() => assetFilter = null)),
              for (final a in listAssets) ...[
                const SizedBox(width: 6),
                FilterChipX(active: assetFilter == a.id, label: a.name, onTap: () => setState(() => assetFilter = a.id)),
              ],
            ]),
          ),
        const SizedBox(height: 8),
        Row(children: [
          FilterChipX(active: zeros == 'hide', label: 'بدون صفر', activeColor: C.cyan, onTap: () => setState(() => zeros = 'hide')),
          const SizedBox(width: 6),
          FilterChipX(active: zeros == 'show', label: 'شامل صفر', activeColor: C.cyan, onTap: () => setState(() => zeros = 'show')),
        ]),
        const SizedBox(height: 12),
        _summary(mode, t, periodEndLabel, issues(t.invalid, t.oversell, 'فروش بیشتر از موجودی')),
        const SizedBox(height: 12),
        if (sorted.isEmpty)
          const Padding(
            padding: EdgeInsets.all(30),
            child: Column(children: [
              Icon(Icons.toll_outlined, size: 28, color: C.slate600),
              SizedBox(height: 8),
              Text('دارایی‌ای برای نمایش نیست.', style: TextStyle(fontSize: 12, color: C.slate500)),
            ]),
          )
        else
          for (final (a, st) in sorted) _assetRow(a, st, mode, issues(st.invalidTradeCount, st.oversellCount, 'فروش بیش از موجودی')),
        if (t.missing > 0)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
                'برای ${_fa(t.missing)} دارایی قیمت پایان دوره در دسترس نیست؛ سود/زیان باز آن‌ها در جمع لحاظ نشده. با ثبت قیمت روزانه یا تراکنش در آن روز، تاریخچه ساخته می‌شود.',
                style: const TextStyle(fontSize: 11, color: C.slate500, height: 1.6)),
          ),
        if (t.invalid > 0 || t.oversell > 0)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: AppCard(
              padding: const EdgeInsets.all(12),
              color: C.amber.withValues(alpha: 0.08),
              borderColor: C.amber.withValues(alpha: 0.3),
              child: Text(
                [
                  if (t.invalid > 0) '${_fa(t.invalid)} رکورد دارایی نامعتبر از محاسبه حذف شد.',
                  if (t.oversell > 0) '${_fa(t.oversell)} مورد فروش بیشتر از موجودی تشخیص داده شد.',
                ].join(' '),
                style: const TextStyle(fontSize: 11, color: C.amber300, height: 1.6),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _summary(String mode, _Totals t, String periodEndLabel, String issueLine) {
    final usd = mode == 'USD';
    final total = usd ? t.realizedUsd + t.unrealizedUsd : t.realizedToman + t.unrealizedToman;
    final realized = usd ? t.realizedUsd : t.realizedToman;
    final open = usd ? t.unrealizedUsd : t.unrealizedToman;
    Widget line(String label, double v, String tip, {bool warn = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(label, style: const TextStyle(fontSize: 12, color: C.slate400)),
              if (warn) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.error_outline, size: 11, color: C.amber300)),
              const Spacer(),
              Money(_signed(v, mode), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _pnlColor(v))),
            ]),
            Text(tip, style: const TextStyle(fontSize: 10, color: C.slate500)),
          ]),
        );
    return AppCard(
      onTap: () => setState(() => summaryOpen = !summaryOpen),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Expanded(child: Text('سود/زیان کل دوره', style: TextStyle(fontSize: 12, color: C.slate400))),
          AnimatedRotation(turns: summaryOpen ? 0.5 : 0, duration: const Duration(milliseconds: 150), child: const Icon(Icons.expand_more, size: 16, color: C.slate500)),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Icon(total >= 0 ? Icons.trending_up : Icons.trending_down, size: 18, color: total >= 0 ? C.emerald400 : C.rose400),
          const SizedBox(width: 6),
          Money(_signed(total, mode), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: _pnlColor(total))),
        ]),
        if (t.missing > 0) Text('${_fa(t.missing)} دارایی بدون قیمت پایان دوره', style: const TextStyle(fontSize: 11, color: C.amber300)),
        if (!summaryOpen) Text('${t.buys} خرید · ${t.sells} فروش — جزئیات', style: const TextStyle(fontSize: 11, color: C.slate500)),
        if (summaryOpen) ...[
          const Divider(color: C.white10, height: 20),
          line('محقق‌شده', realized, 'از تراکنش‌های فروش انجام‌شده در این دوره'),
          const Divider(color: C.white10, height: 12),
          line('باز — $periodEndLabel', open, t.missing > 0 ? '${_fa(t.missing)} دارایی بدون قیمت تاریخی لحاظ نشده' : 'بر اساس قیمت ثبت‌شده در پایان دوره', warn: t.missing > 0),
          Text('${t.buys} خرید · ${t.sells} فروش', style: const TextStyle(fontSize: 11, color: C.slate500)),
          if (issueLine.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(issueLine, style: const TextStyle(fontSize: 11, color: C.amber300))),
        ],
      ]),
    );
  }

  Widget _assetRow(Asset a, AssetPeriodStats st, String mode, String issueLine) {
    final usd = mode == 'USD';
    final open = openRows.contains(a.id);
    final realized = usd ? st.realizedUsd : st.realizedToman;
    final unreal = usd ? st.periodUnrealizedUsd : st.periodUnrealizedToman;
    final double? total = st.periodUnrealizedAvailable ? realized + unreal : (st.hadActivity ? realized : null);
    final decimals = a.decimalPlaces;
    final stale = st.periodUnrealizedAvailable && st.periodEndPriceSourceDate != null && !st.periodEndPriceIsLive ? parseJalaali(st.periodEndPriceSourceDate!) : null;

    Widget fact(String label, Widget value, [String? hint]) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: C.white5, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 10, color: C.slate500)),
              const SizedBox(height: 2),
              value,
              if (hint != null) Text(hint, style: const TextStyle(fontSize: 9, color: C.slate500)),
            ]),
          ),
        );

    Widget trade(IconData icon, String label, SideAggregate side) => Expanded(
          child: Opacity(
            opacity: side.units == 0 ? 0.5 : 1,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: C.white5, borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(icon, size: 12, color: C.slate400),
                  const SizedBox(width: 4),
                  Text(label, style: const TextStyle(fontSize: 11, color: C.slate400)),
                  Text(' (${side.count})', style: const TextStyle(fontSize: 10, color: C.slate500)),
                ]),
                const SizedBox(height: 4),
                Text('${formatAssetAmount(side.units, decimals)} ${a.unit}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: C.slate200)),
                const Text('میانگین قیمت', style: TextStyle(fontSize: 10, color: C.slate500)),
                Money(formatCurrency(usd ? side.avgPriceUsd : side.avgPriceToman, mode), style: const TextStyle(fontSize: 12, color: C.slate300)),
              ]),
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            onTap: () => setState(() => open ? openRows.remove(a.id) : openRows.add(a.id)),
            child: Row(children: [
              EntityIcon(iconUrl: a.iconUrl, fallback: Icons.toll_outlined, size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.slate200)),
                  Text('${formatAssetAmount(st.endHoldings, decimals)} ${a.unit}${st.hadActivity ? '' : ' · بدون فعالیت'}', style: const TextStyle(fontSize: 11, color: C.slate500)),
                ]),
              ),
              total != null
                  ? Money(_signed(total, mode), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _pnlColor(total, C.slate500)))
                  : const Text('—', style: TextStyle(color: C.slate500)),
              AnimatedRotation(turns: open ? 0.5 : 0, duration: const Duration(milliseconds: 150), child: const Icon(Icons.expand_more, size: 16, color: C.slate500)),
            ]),
          ),
          if (open) ...[
            const SizedBox(height: 10),
            if (st.hadActivity)
              Row(children: [trade(Icons.arrow_downward, 'خرید دوره', st.bought), const SizedBox(width: 8), trade(Icons.arrow_upward, 'فروش دوره', st.sold)])
            else
              const Text('در این دوره تراکنشی ثبت نشده.', style: TextStyle(fontSize: 11, color: C.slate500)),
            if (issueLine.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(issueLine, style: const TextStyle(fontSize: 11, color: C.amber300))),
            const SizedBox(height: 8),
            Row(children: [
              fact('محقق‌شده', Money(_signed(realized, mode), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _pnlColor(realized, C.slate500)))),
              const SizedBox(width: 8),
              st.periodUnrealizedAvailable
                  ? fact('باز', Money(_signed(unreal, mode), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _pnlColor(unreal, C.slate400))),
                      stale != null ? 'قیمت: ${formatJalaaliHuman(stale)}' : null)
                  : fact('باز', const Row(children: [Text('—', style: TextStyle(color: C.slate500)), SizedBox(width: 4), Icon(Icons.info_outline, size: 11, color: C.slate500)])),
            ]),
            if (st.endHoldings > 0) ...[
              const SizedBox(height: 8),
              Row(children: [fact('میانگین قیمت خرید (پایان دوره)', Money(formatCurrency(usd ? st.endAvgCostUsd : st.endAvgCostToman, mode), style: const TextStyle(fontSize: 12, color: C.slate300)))]),
            ],
          ],
        ]),
      ),
    );
  }
}
