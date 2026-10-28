// Ports of DailyPricesView.tsx, PriceSourceAdvancedSection.tsx,
// PriceSourceCatalogSection.tsx and prices/utils/auto-price-health.ts.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/logic/ledger.dart';
import '../../core/models.dart';
import '../../core/services/prices.dart';
import '../../core/store.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/toast.dart';
import '../../core/ui/widgets.dart';
import '../../core/utils/digits.dart';
import '../../core/utils/jalali.dart';
import '../transactions/tx_logic.dart';

const _rateOrder = ['USD', 'TRY', 'EUR'];

String _tomanInput(double v) => !v.isFinite || v <= 0 ? '' : v.round().toString();
String _usdInput(double v) => !v.isFinite || v <= 0 ? '' : v.toStringAsFixed(2);

/// Slugs with fetch keys that are bound to at least one asset.
List<String> boundFetchablePriceSourceSlugs(Iterable<String?> ids, List<PriceSource> catalog) {
  final bound = <String>{for (final id in ids) if (id != null && id.isNotEmpty) id};
  return bound.where((slug) {
    final s = catalog.where((c) => c.slug == slug).firstOrNull;
    return s?.fetchKey != null && s!.fetchKey!.isNotEmpty && !s.deprecated;
  }).toList();
}

class PricesScreen extends StatefulWidget {
  final Map<String, String> query;
  const PricesScreen({super.key, required this.query});
  @override
  State<PricesScreen> createState() => _PricesScreenState();
}

class _PricesScreenState extends State<PricesScreen> {
  bool saving = false, refreshing = false;
  late bool advancedOpen = widget.query['advanced'] == '1';
  final Map<String, (String, String)> local = {}; // assetId → (toman, usd)
  String localUsd = '';
  final Map<String, String> otherRates = {};
  final Map<String, (String, String)> conv = {}; // slug → (conversion_rate, usd_factor)
  late final PortfolioStore _s = context.read<PortfolioStore>();

  @override
  void initState() {
    super.initState();
    _syncFromStore();
  }

  List<String> get _otherCurrencies {
    final used = {for (final w in _s.wallets) if (w.currency != 'IRT' && w.currency != 'USD') w.currency};
    return _rateOrder.where((c) => c != 'USD' && used.contains(c)).toList();
  }

  List<String> get _boundSlugs => boundFetchablePriceSourceSlugs(_s.assets.map((a) => a.priceSourceId), _s.priceSourceCatalog);

  void _syncFromStore() {
    local
      ..clear()
      ..addAll({for (final a in _s.assets) a.id: (_tomanInput(a.priceToman), _usdInput(a.priceUsd))});
    localUsd = _s.usdRate > 0 ? jsNumStr(_s.usdRate) : '';
    otherRates.clear();
    for (final c in _otherCurrencies) {
      final r = _s.currencyRates.where((r) => r.currency == c).firstOrNull;
      otherRates[c] = r != null ? jsNumStr(r.tomanPerUnit) : '';
    }
    _syncConv();
  }

  void _syncConv() {
    final bySlug = {for (final r in _s.priceSourceSettings) r.slug: r};
    conv.clear();
    for (final slug in _boundSlugs) {
      final r = bySlug[slug];
      conv[slug] = (r != null ? jsNumStr(r.conversionRate) : '1', r?.usdFactor == 'multiply' || r?.usdFactor == 'divide' ? r!.usdFactor : 'none');
    }
  }

  double get _effectiveUsd {
    final v = n(localUsd);
    return v.isFinite && v > 0 ? v : 0;
  }

  bool _canon(String c) => c.isNotEmpty && c != '.' && !n(c).isNaN;

  void _onPrice(String id, bool toman, String c) {
    final cur = local[id] ?? ('', '');
    var t = cur.$1, u = cur.$2;
    if (toman) {
      t = c;
      if (_canon(c) && _effectiveUsd > 0) u = _usdInput(n(c) / _effectiveUsd);
    } else {
      u = c;
      if (_canon(c)) t = _tomanInput(n(c) * _effectiveUsd);
    }
    setState(() => local[id] = (t, u));
  }

  void _onUsdRate(String c) {
    final newUsd = c.isEmpty || c == '.' ? 0.0 : n(c);
    setState(() {
      localUsd = c;
      if (c.isNotEmpty && c != '.' && newUsd.isNaN) return;
      for (final id in local.keys.toList()) {
        final row = local[id]!;
        final u = n(row.$2);
        if (row.$2.isNotEmpty && !u.isNaN) local[id] = (_tomanInput(u * newUsd), row.$2);
      }
    });
  }

  Future<void> _refreshProviders() async {
    setState(() => refreshing = true);
    try {
      final refreshable = _s.assets.where((a) => a.priceSourceId != null).toList();
      final slugs = [kUsdRateSourceSlug, ...refreshable.map((a) => a.priceSourceId!)];
      final result = await fetchProviderQuotesDetailed(slugs, catalogToApiSources(_s.priceSourceCatalog));
      final usdQuote = result.quotes.where((q) => q.slug == kUsdRateSourceSlug).firstOrNull;
      final nextUsd = usdQuote != null && usdQuote.priceToman > 0 ? usdQuote.priceToman : _effectiveUsd;
      final quotes = applyConversionRatesToQuotes(mergeGlobalUsdDollarQuotes(result.quotes, refreshable, nextUsd), buildConversionConfigMap(_s.priceSourceSettings), nextUsd);
      var updated = 0;
      if (quotes.isNotEmpty) {
        final bySlug = {for (final q in quotes) q.slug: q};
        setState(() {
          if (usdQuote != null && usdQuote.priceToman > 0) localUsd = jsNumStr(usdQuote.priceToman);
          for (final a in refreshable) {
            final q = bySlug[a.priceSourceId];
            if (q == null) continue;
            local[a.id] = (_tomanInput(q.priceToman), nextUsd > 0 ? _usdInput(q.priceToman / nextUsd) : (local[a.id]?.$2 ?? ''));
          }
        });
        updated = quotes.where((q) => q.slug != kUsdRateSourceSlug).length;
      }
      if (updated > 0) {
        Toast.success('$updated قیمت دارایی و نرخ دلار بروزرسانی شد.');
      } else {
        Toast.info('قیمت معتبری برای بروزرسانی دریافت نشد.');
      }
      if (result.failedProviders.isNotEmpty || result.unresolvedSlugs.isNotEmpty || result.unknownRequestedSlugs.isNotEmpty) {
        final detail = [
          result.failedProviders.map((p) => '${p.$1}: ${p.$2}').join(' | '),
          result.unresolvedSlugs.map((u) => '${u.$1}: ${u.$2}').join(' | '),
          if (result.unknownRequestedSlugs.isNotEmpty) 'unknown: ${result.unknownRequestedSlugs.join(', ')}',
        ].where((x) => x.isNotEmpty).join(' | ');
        Toast.error('بخشی از بروزرسانی انجام نشد. $detail', durationMs: 10000);
      }
    } catch (e) {
      Toast.error('دریافت قیمت از منبع بیرونی ناموفق بود. $e', durationMs: 14000);
    } finally {
      if (mounted) setState(() => refreshing = false);
    }
  }

  /// usePriceSourceAdvancedSave().save
  Future<bool> _saveConv() async {
    final user = _s.user;
    if (user == null) return false;
    final now = DateTime.now().toUtc().toIso8601String();
    final rows = <Json>[];
    for (final slug in _boundSlugs) {
      final src = findPriceSourceInCatalog(slug, _s.priceSourceCatalog);
      if (src?.fetchKey == null) continue;
      final row = conv[slug];
      if (row == null) continue;
      final raw = row.$1.trim();
      final rate = raw.isEmpty || raw == '.' ? 1.0 : n(raw);
      if (!rate.isFinite || rate <= 0) {
        Toast.error('ضریب تبدیل نامعتبر برای «${src!.label}».');
        return false;
      }
      rows.add({'user_id': user.id, 'slug': slug, 'conversion_rate': rate, 'usd_factor': row.$2, 'updated_at': now});
    }
    if (rows.isEmpty) return true;
    final data = await sb.from('price_source_settings').upsert(rows, onConflict: 'user_id,slug').select();
    final fresh = (data as List).cast<Json>().map(PriceSourceSetting.fromJson).toList();
    _s.update((st) => st.priceSourceSettings = mergeById(st.priceSourceSettings, fresh, (r) => r.slug));
    return true;
  }

  Future<void> _save() async {
    final user = _s.user;
    if (user == null) return;
    setState(() => saving = true);
    try {
      for (final c in _otherCurrencies) {
        final raw = (otherRates[c] ?? '').trim();
        if (raw.isEmpty) continue;
        final v = n(raw);
        if (!v.isFinite || v <= 0) {
          Toast.error('نرخ نامعتبر برای ${currencyMeta(c).label}.');
          return;
        }
      }
      final assetUpdates = [
        for (final a in _s.assets)
          {
            'id': a.id,
            'user_id': a.userId,
            'category_id': a.categoryId,
            'name': a.name,
            'unit': a.unit,
            'decimal_places': a.decimalPlaces,
            'price_toman': n(local[a.id]?.$1 ?? ''),
            'price_usd': n(local[a.id]?.$2 ?? ''),
            'icon_url': a.iconUrl,
            'price_source_id': a.priceSourceId,
            'include_in_profit_loss': a.includeInProfitLoss,
            'include_in_balance': a.includeInBalance ?? true,
          },
      ];
      final now = DateTime.now().toUtc().toIso8601String();
      final rateRows = <Json>[];
      final usdNum = n(localUsd);
      if (usdNum.isFinite && usdNum > 0) rateRows.add({'user_id': user.id, 'currency': 'USD', 'toman_per_unit': usdNum, 'updated_at': now});
      for (final c in _otherCurrencies) {
        final raw = (otherRates[c] ?? '').trim();
        if (raw.isEmpty) continue;
        rateRows.add({'user_id': user.id, 'currency': c, 'toman_per_unit': n(raw), 'updated_at': now});
      }
      final results = await Future.wait([
        sb.from('assets').upsert(assetUpdates).select(),
        if (rateRows.isNotEmpty) sb.from('currency_rates').upsert(rateRows, onConflict: 'user_id,currency').select(),
      ]);
      if (rateRows.isNotEmpty) {
        final d = formatJalaali(todayJalaaliTehran());
        await Future.wait([for (final r in rateRows) recordRateHistory(user.id, r['currency'] as String, d, r['toman_per_unit'] as double, 'manual')]);
      }
      if (!await _saveConv()) return;
      final freshAssets = (results[0] as List).cast<Json>().map(Asset.fromJson).toList();
      final freshRates = rateRows.isNotEmpty ? (results[1] as List).cast<Json>().map(CurrencyRate.fromJson).toList() : <CurrencyRate>[];
      _s.update((st) {
        st.assets = freshAssets;
        if (freshRates.isNotEmpty) st.currencyRates = mergeCurrencyRates(st.currencyRates, freshRates);
      });
      final today = todayStr();
      final snapshot = [
        for (final a in assetUpdates)
          if ((a['price_toman'] as double) > 0 && (a['price_usd'] as double) >= 0)
            {'user_id': user.id, 'asset_id': a['id'], 'date_string': today, 'price_toman': a['price_toman'], 'price_usd': a['price_usd'], 'source': 'manual'},
      ];
      if (snapshot.isNotEmpty) {
        try {
          final dp = await sb.from('daily_prices').upsert(snapshot, onConflict: 'user_id,asset_id,date_string').select();
          final fresh = (dp as List).cast<Json>().map(DailyPrice.fromJson).toList();
          _s.update((st) => st.dailyPrices = mergeDailyPrices(st.dailyPrices, fresh));
        } catch (_) {
          Toast.info('قیمت‌ها ذخیره شد؛ اما ثبت تاریخچه‌ی روزانه ناموفق بود.');
        }
      }
      Toast.success('قیمت‌ها و نرخ‌ها ذخیره شد.');
      if (mounted) Navigator.pop(context);
    } catch (_) {
      Toast.error('خطا در ذخیره.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<PortfolioStore>();
    final today = todayStr();
    final autoAssets = s.assets.where((a) => a.priceSourceId != null).toList();
    final autoIds = autoAssets.map((a) => a.id).toSet();
    final synced = s.dailyPrices.where((r) => r.dateString == today && r.source == 'auto' && autoIds.contains(r.assetId)).map((r) => r.assetId).toSet().length;
    final missing = autoAssets.length - synced;
    final healthy = missing == 0;
    final visibleAssets = s.assets.where((a) => a.includeInBalance != false && calculateAssetStats(a, s.transactions, 'TOMAN', s.usdRate).totalAmount > 0).toList();
    final others = _otherCurrencies;

    return SubPage(
      title: 'قیمت‌ها و نرخ‌ها',
      actions: [
        IconButton(
          onPressed: refreshing ? null : _refreshProviders,
          icon: refreshing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh, size: 20),
        ),
      ],
      bottom: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: AppButton(saving ? 'در حال ذخیره...' : 'ذخیره', expand: true, onPressed: saving ? null : _save),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        if (autoAssets.isNotEmpty) ...[
          AppCard(
            padding: const EdgeInsets.all(12),
            color: (healthy ? C.emerald : C.amber).withValues(alpha: 0.1),
            borderColor: (healthy ? C.emerald : C.amber).withValues(alpha: 0.2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(healthy ? Icons.refresh : Icons.error_outline, size: 14, color: healthy ? C.emerald300 : C.amber300),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  healthy
                      ? 'قیمت خودکار ${toPersianDigits(synced)} دارایی امروز دریافت شده (بروزرسانی روزانه ~۰۹:۰۰).'
                      : 'قیمت خودکار ${toPersianDigits(missing)} از ${toPersianDigits(autoAssets.length)} دارایی امروز دریافت نشده — دکمه بروزرسانی را بزنید یا منبع قیمت را بررسی کنید.',
                  style: TextStyle(fontSize: 11, height: 1.6, color: healthy ? const Color(0xFFA7F3D0) : const Color(0xFFFDE68A)),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
        ],
        Field(label: 'نرخ دلار (تومان)', child: NumberInput(value: localUsd, onChanged: _onUsdRate)),
        if (others.isNotEmpty)
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('نرخ ارزهای کیف پول', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: C.slate400)),
              const SizedBox(height: 8),
              for (final c in others)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: C.hover, borderRadius: BorderRadius.circular(10)),
                      child: Text(currencyMeta(c).symbol, textDirection: TextDirection.ltr, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(currencyMeta(c).label, style: const TextStyle(fontSize: 12, color: C.slate200)),
                        Text('1 $c = ? تومان', textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 10, color: C.slate500)),
                      ]),
                    ),
                    SizedBox(width: 140, child: NumberInput(value: otherRates[c] ?? '', hint: '0', onChanged: (v) => otherRates[c] = v)),
                  ]),
                ),
            ]),
          ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('دریافت قیمت زنده با دکمهٔ رفرش یا رفرش داشبورد انجام می‌شود.', style: TextStyle(fontSize: 11, color: C.slate500)),
        ),
        const Text('قیمت دارایی‌ها', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: C.slate400)),
        const SizedBox(height: 8),
        for (final a in visibleAssets)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppCard(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(a.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: Field(label: 'دلار', child: NumberInput(value: local[a.id]?.$2 ?? '', suffix: '\$', onChanged: (v) => _onPrice(a.id, false, v)))),
                  const SizedBox(width: 8),
                  Expanded(child: Field(label: 'تومان', child: NumberInput(value: local[a.id]?.$1 ?? '', suffix: 'ت', onChanged: (v) => _onPrice(a.id, true, v)))),
                ]),
              ]),
            ),
          ),
        if (visibleAssets.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('دارایی با مقدار بیشتر از صفر برای بروزرسانی قیمت وجود ندارد.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: C.slate500)),
          ),
        const SizedBox(height: 8),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ListTile(
              title: const Text('تنظیمات پیشرفته', style: TextStyle(fontSize: 13, color: C.slate200)),
              trailing: AnimatedRotation(turns: advancedOpen ? 0.5 : 0, duration: const Duration(milliseconds: 150), child: const Icon(Icons.expand_more, color: C.slate400)),
              onTap: () => setState(() => advancedOpen = !advancedOpen),
            ),
            if (advancedOpen)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _PriceSourceCatalog(onChanged: () => setState(_syncConv)),
                  const Divider(color: C.white10, height: 28),
                  const Text('ضرایب تبدیل', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: C.slate300)),
                  const SizedBox(height: 6),
                  _advanced(s),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _advanced(PortfolioStore s) {
    final sources = _boundSlugs.map((slug) => findPriceSourceInCatalog(slug, s.priceSourceCatalog)).whereType<PriceSource>().toList();
    if (sources.isEmpty) {
      return const Text('هیچ دارایی با منبع قیمت خودکار نداری. پس از اتصال منبع به یک دارایی، تنظیمات پیشرفته اینجا نمایش داده می‌شود.',
          style: TextStyle(fontSize: 11, color: C.slate500, height: 1.6));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('فقط برای منابعی که به دارایی‌هایت متصل‌اند. معمولاً نیازی به تغییر نیست.', style: TextStyle(fontSize: 11, color: C.slate500)),
      const SizedBox(height: 8),
      for (final src in sources)
        Builder(builder: (_) {
          final row = conv[src.slug] ?? ('1', 'none');
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: C.hover, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(src.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: C.slate200)),
              const SizedBox(height: 8),
              Field(label: 'ضریب تبدیل', child: NumberInput(value: row.$1, hint: '1', onChanged: (v) => conv[src.slug] = (v, (conv[src.slug] ?? row).$2))),
              const FieldLabel('نرخ دلار'),
              Segmented<String>(
                options: const [('none', 'بدون دلار'), ('multiply', '× دلار'), ('divide', '÷ دلار')],
                value: row.$2,
                onChanged: (v) => setState(() => conv[src.slug] = ((conv[src.slug] ?? row).$1, v)),
              ),
            ]),
          );
        }),
    ]);
  }
}

class _PriceSourceCatalog extends StatefulWidget {
  final VoidCallback onChanged;
  const _PriceSourceCatalog({required this.onChanged});
  @override
  State<_PriceSourceCatalog> createState() => _PriceSourceCatalogState();
}

class _PriceSourceCatalogState extends State<_PriceSourceCatalog> {
  bool adding = false, saving = false;
  String? editingSlug;
  String label = '', fetchKey = '', provider = 'abantether', slug = '';
  int formKey = 0;

  void _reset([String p = 'abantether']) {
    label = fetchKey = slug = '';
    provider = p;
    formKey++;
  }

  void _cancel() => setState(() {
        adding = false;
        editingSlug = null;
        _reset();
      });

  Future<void> _saveNew(PortfolioStore s) async {
    final user = s.user;
    if (user == null) return;
    final l = label.trim(), fk = fetchKey.trim(), sl = slug.trim().toLowerCase();
    if (l.isEmpty) return Toast.error('نام منبع را وارد کن.');
    if (fk.isEmpty) return Toast.error('کلید دریافت (fetch key) را وارد کن.');
    if (!isValidSlug(sl)) return Toast.error('شناسه (slug) نامعتبر است.');
    if (s.priceSources.any((x) => x.slug == sl)) return Toast.error('این شناسه قبلاً ثبت شده.');
    setState(() => saving = true);
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final data = await sb
          .from('price_sources')
          .insert({
            'user_id': user.id,
            'slug': sl,
            'provider': provider,
            'label': l,
            'fetch_key': fk,
            'updates_rate': null,
            'deprecated': false,
            'is_builtin': false,
            'created_at': now,
            'updated_at': now,
          })
          .select()
          .single();
      final setting = {'user_id': user.id, 'slug': sl, 'conversion_rate': 1, 'usd_factor': 'none', 'updated_at': now};
      await sb.from('price_source_settings').upsert(setting, onConflict: 'user_id,slug');
      final saved = PriceSourceRecord.fromJson(data);
      s.update((st) {
        st.priceSources = [...st.priceSources, saved]..sort((a, b) => a.slug.compareTo(b.slug));
        st.priceSourceSettings = [...st.priceSourceSettings.where((r) => r.slug != sl), PriceSourceSetting.fromJson(setting)];
      });
      Toast.success('منبع قیمت اضافه شد.');
      _cancel();
      widget.onChanged();
    } catch (_) {
      Toast.error('خطا در افزودن منبع قیمت.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _saveEdit(PortfolioStore s) async {
    final user = s.user;
    final editing = editingSlug;
    if (user == null || editing == null) return;
    final src = s.priceSources.where((x) => x.slug == editing).firstOrNull;
    if (src == null) return;
    final l = label.trim(), fk = fetchKey.trim();
    if (l.isEmpty) return Toast.error('نام منبع را وارد کن.');
    if (fk.isEmpty) return Toast.error('کلید دریافت (fetch key) را وارد کن.');
    setState(() => saving = true);
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final patch = src.isBuiltin ? {'label': l, 'updated_at': now} : {'label': l, 'fetch_key': fk, 'updated_at': now};
      final data = await sb.from('price_sources').update(patch).eq('user_id', user.id).eq('slug', editing).select().single();
      final saved = PriceSourceRecord.fromJson(data);
      s.update((st) => st.priceSources = [for (final r in st.priceSources) r.slug == editing ? saved : r]);
      Toast.success('منبع قیمت به‌روز شد.');
      _cancel();
      widget.onChanged();
    } catch (_) {
      Toast.error('خطا در ذخیره منبع قیمت.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _remove(PortfolioStore s, PriceSourceRecord src) async {
    final user = s.user;
    if (user == null) return;
    if (src.isBuiltin) return Toast.error('منابع پیش‌فرض قابل حذف نیستند.');
    if (s.assets.any((a) => a.priceSourceId == src.slug)) return Toast.error('این منبع به یک دارایی متصل است — ابتدا اتصال را قطع کن.');
    setState(() => saving = true);
    try {
      await sb.from('price_sources').delete().eq('user_id', user.id).eq('slug', src.slug);
      s.update((st) => st.priceSources = st.priceSources.where((r) => r.slug != src.slug).toList());
      Toast.success('منبع حذف شد.');
      if (editingSlug == src.slug) _cancel();
      widget.onChanged();
    } catch (_) {
      Toast.error('خطا در حذف منبع.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<PortfolioStore>();
    final visible = s.priceSources.where((x) => !x.deprecated).toList();
    final editing = editingSlug == null ? null : s.priceSources.where((x) => x.slug == editingSlug).firstOrNull;
    final locked = editing?.isBuiltin == true;
    final showForm = adding || editingSlug != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Expanded(child: Text('منابع قیمت', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: C.slate300))),
        if (!showForm)
          TextButton.icon(
            onPressed: () => setState(() {
              _reset();
              editingSlug = null;
              adding = true;
            }),
            icon: const Icon(Icons.add, size: 14),
            label: const Text('افزودن'),
          ),
      ]),
      const Text('ارائه‌دهنده (آبان‌تتر / زرپی) ثابت است؛ نام، کلید دریافت و شناسه را می‌توانی سفارشی کنی.', style: TextStyle(fontSize: 11, color: C.slate500, height: 1.6)),
      const SizedBox(height: 8),
      for (final src in visible)
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: C.hover, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(src.label, style: const TextStyle(fontSize: 12, color: C.slate200)),
                Text('${src.slug} · ${src.provider} · ${src.fetchKey ?? ''}', textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 10, color: C.slate500)),
              ]),
            ),
            TextButton(
              onPressed: () => setState(() {
                adding = false;
                editingSlug = src.slug;
                label = src.label;
                fetchKey = src.fetchKey ?? '';
                provider = src.provider;
                slug = src.slug;
                formKey++;
              }),
              child: const Text('ویرایش', style: TextStyle(fontSize: 11)),
            ),
            if (!src.isBuiltin) IconButton(onPressed: saving ? null : () => _remove(s, src), icon: const Icon(Icons.delete_outline, size: 16, color: C.rose300)),
          ]),
        ),
      if (showForm)
        Container(
          key: ValueKey(formKey),
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: C.inset, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.cyan.withValues(alpha: 0.3))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(adding ? 'منبع جدید' : 'ویرایش منبع', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 8),
            if (adding) ...[
              const FieldLabel('ارائه‌دهنده'),
              Segmented<String>(
                options: const [('abantether', 'آبان‌تتر'), ('zarpay', 'زرپی')],
                value: provider,
                onChanged: (v) => setState(() {
                  provider = v;
                  slug = suggestSlug(v, fetchKey);
                }),
              ),
              const SizedBox(height: 10),
            ],
            Field(label: 'نام نمایشی', child: AppTextField(value: label, onChanged: (v) => label = v)),
            Field(
              label: 'کلید دریافت (fetch key)',
              child: AppTextField(
                value: fetchKey,
                ltr: true,
                enabled: !locked,
                onChanged: (v) => setState(() {
                  fetchKey = v;
                  if (adding) slug = suggestSlug(provider, v);
                }),
              ),
            ),
            if (adding) Field(label: 'شناسه (slug)', child: AppTextField(value: slug, ltr: true, onChanged: (v) => setState(() => slug = v.trim().toLowerCase()))),
            Row(children: [
              Expanded(child: AppButton(saving ? 'در حال ذخیره...' : 'ذخیره', expand: true, onPressed: saving ? null : () => adding ? _saveNew(s) : _saveEdit(s))),
              const SizedBox(width: 8),
              AppButton('انصراف', variant: BtnVariant.secondary, onPressed: saving ? null : _cancel),
            ]),
          ]),
        ),
    ]);
  }
}
