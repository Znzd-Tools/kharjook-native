// Ports of price-sources.ts, price-source-catalog.ts, conversion-rate.ts,
// provider-refresh.ts and rate-history-store.ts.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../models.dart';
import '../utils/jalali.dart';
import '../logic/rate_history.dart';

SupabaseClient get sb => Supabase.instance.client;

const kAppGlobalUsdSlug = 'app.dollar';
const kUsdRateSourceSlug = 'abantether.usdt';

class PriceSource {
  final String slug;
  final String provider;
  final String label;
  final String? fetchKey;
  final String? updatesRate;
  final bool deprecated;
  const PriceSource(this.slug, this.provider, this.label, this.fetchKey, this.updatesRate, {this.deprecated = false});
}

const kDefaultPriceSources = <PriceSource>[
  PriceSource(kAppGlobalUsdSlug, 'abantether', 'دلار', 'USDT', 'USD'),
  PriceSource('abantether.usdt', 'abantether', 'تتر · آبان‌تتر', 'USDT', null),
  PriceSource('abantether.btc', 'abantether', 'بیت‌کوین · آبان‌تتر', 'BTC', null),
  PriceSource('abantether.sol', 'abantether', 'سولانا · آبان‌تتر', 'SOL', null),
  PriceSource('abantether.eth', 'abantether', 'اتریوم · آبان‌تتر', 'ETH', null),
  PriceSource('abantether.paxg', 'abantether', 'پکس گلد · آبان‌تتر', 'PAXG', null),
  PriceSource('abantether.ast_brsbox', 'abantether', 'بورس باکس · آبان‌تتر', 'AST_BRSBOX', null),
  PriceSource('abantether.ast_gold', 'abantether', 'طلا · آبان‌تتر', 'AST_GOLD', null),
  PriceSource('abantether.copxon', 'abantether', 'مس · آبان‌تتر', 'COPXON', null),
  PriceSource('abantether.slvon', 'abantether', 'نقره · آبان‌تتر', 'SLVON', null),
  PriceSource('zarpay.gold', 'zarpay', 'طلا ۱۸ عیار · زرپی', 'GOLD', null),
  PriceSource('zarpay.silver', 'zarpay', 'نقره · زرپی', 'SILVER', null),
  PriceSource('zarpay.copper', 'zarpay', 'مس · زرپی', 'COPPER', null),
];

PriceSource recordToPriceSource(PriceSourceRecord r) =>
    PriceSource(r.slug, r.provider, r.label, r.fetchKey, r.updatesRate, deprecated: r.deprecated);

List<PriceSource> recordsToCatalog(List<PriceSourceRecord> records) => records.map(recordToPriceSource).toList();

PriceSource? findPriceSourceInCatalog(String? slug, List<PriceSource> catalog) {
  if (slug == null || slug.isEmpty) return null;
  for (final s in catalog) {
    if (s.slug == slug) return s;
  }
  return null;
}

bool isValidSlug(String slug) => RegExp(r'^[a-z0-9][a-z0-9._-]*$').hasMatch(slug);

String suggestSlug(String provider, String fetchKey) {
  final n = fetchKey.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9._-]+'), '_');
  return '$provider.${n.isEmpty ? 'custom' : n}';
}

Future<List<PriceSourceRecord>> ensureDefaultPriceSources(String userId) async {
  final existing = await sb.from('price_sources').select('slug').eq('user_id', userId).limit(1);
  if ((existing as List).isNotEmpty) return [];
  final now = DateTime.now().toUtc().toIso8601String();
  final rows = kDefaultPriceSources
      .map((s) => {
            'user_id': userId,
            'slug': s.slug,
            'provider': s.provider,
            'label': s.label,
            'fetch_key': s.fetchKey,
            'updates_rate': s.updatesRate,
            'deprecated': s.deprecated,
            'is_builtin': true,
            'created_at': now,
            'updated_at': now,
          })
      .toList();
  final data = await sb.from('price_sources').upsert(rows, onConflict: 'user_id,slug', ignoreDuplicates: true).select();
  final settingsRows = rows
      .map((r) => {'user_id': userId, 'slug': r['slug'], 'conversion_rate': 1, 'usd_factor': 'none', 'updated_at': now})
      .toList();
  try {
    await sb.from('price_source_settings').upsert(settingsRows, onConflict: 'user_id,slug', ignoreDuplicates: true);
  } catch (_) {}
  final list = (data as List).map((e) => PriceSourceRecord.fromJson(e as Json)).toList();
  return list.isNotEmpty ? list : rows.map(PriceSourceRecord.fromJson).toList();
}

// ─── Conversion ────────────────────────────────────────────────────────────

class ConversionConfig {
  final double conversionRate;
  final String usdFactor;
  const ConversionConfig(this.conversionRate, this.usdFactor);
}

const _defaultConversion = ConversionConfig(1, 'none');

Map<String, ConversionConfig> buildConversionConfigMap(List<PriceSourceSetting> settings) {
  final map = <String, ConversionConfig>{};
  for (final row in settings) {
    final r = row.conversionRate;
    if (!r.isFinite || r <= 0) continue;
    final f = row.usdFactor == 'multiply' || row.usdFactor == 'divide' ? row.usdFactor : 'none';
    map[row.slug] = ConversionConfig(r, f);
  }
  return map;
}

ConversionConfig conversionConfigForSlug(String slug, Map<String, ConversionConfig> configs) => configs[slug] ?? _defaultConversion;

double transformProviderPriceToman(double raw, ConversionConfig c, double usd) {
  var price = raw * c.conversionRate;
  if (c.usdFactor == 'multiply' && usd > 0) {
    price *= usd;
  } else if (c.usdFactor == 'divide' && usd > 0) {
    price /= usd;
  }
  return price;
}

class ProviderQuote {
  final String slug;
  final String provider;
  final double priceToman;
  final String fetchedAt;
  ProviderQuote(this.slug, this.provider, this.priceToman, this.fetchedAt);
  factory ProviderQuote.fromJson(Json j) =>
      ProviderQuote(j['slug'] as String, (j['provider'] ?? '') as String, numOr0(j['priceToman']), (j['fetchedAt'] ?? '') as String);
  ProviderQuote withPrice(double p) => ProviderQuote(slug, provider, p, fetchedAt);
}

List<ProviderQuote> applyConversionRatesToQuotes(List<ProviderQuote> quotes, Map<String, ConversionConfig> configs, double usd) =>
    quotes.map((q) {
      final p = transformProviderPriceToman(q.priceToman, conversionConfigForSlug(q.slug, configs), usd);
      return p == q.priceToman ? q : q.withPrice(p);
    }).toList();

List<ProviderQuote> mergeGlobalUsdDollarQuotes(List<ProviderQuote> quotes, List<Asset> assets, double usd) {
  if (!(usd > 0)) return quotes;
  if (!assets.any((a) => a.priceSourceId == kAppGlobalUsdSlug)) return quotes;
  final merged = quotes.where((q) => q.slug != kAppGlobalUsdSlug).toList();
  merged.add(ProviderQuote(kAppGlobalUsdSlug, 'app', usd, DateTime.now().toUtc().toIso8601String()));
  return merged;
}

class QuoteFetchResult {
  final List<ProviderQuote> quotes;
  final List<(String, String)> failedProviders;
  final List<(String, String)> unresolvedSlugs;
  final List<String> unknownRequestedSlugs;
  QuoteFetchResult(this.quotes, this.failedProviders, this.unresolvedSlugs, this.unknownRequestedSlugs);
}

List<Json> catalogToApiSources(List<PriceSource> catalog) => catalog
    .where((s) => s.fetchKey != null && s.fetchKey!.isNotEmpty)
    .map((s) => {'slug': s.slug, 'provider': s.provider, 'fetchKey': s.fetchKey})
    .toList();

/// Calls the web app's public `/api/prices/quotes` route (same as the PWA).
Future<QuoteFetchResult> fetchProviderQuotesDetailed(List<String> slugs, [List<Json>? sources]) async {
  final unique = slugs.where((s) => s.isNotEmpty).toSet().toList();
  if (unique.isEmpty) return QuoteFetchResult([], [], [], []);
  final url = Uri.parse('${AppConfig.apiBaseUrl}/api/prices/quotes');
  final body = jsonEncode({'slugs': unique, if (sources != null && sources.isNotEmpty) 'sources': sources});
  Future<http.Response> doFetch() =>
      http.post(url, headers: {'content-type': 'application/json'}, body: body).timeout(const Duration(seconds: 30));
  http.Response res;
  try {
    res = await doFetch();
  } catch (_) {
    await Future.delayed(const Duration(milliseconds: 700));
    res = await doFetch();
  }
  if (res.statusCode >= 502 && res.statusCode <= 504) {
    await Future.delayed(const Duration(milliseconds: 600));
    res = await doFetch();
  }
  final raw = utf8.decode(res.bodyBytes);
  if (res.statusCode < 200 || res.statusCode >= 300) {
    final hint = raw.length > 400 ? raw.substring(0, 400) : raw;
    throw Exception('درخواست قیمت ناموفق (${res.statusCode}): ${hint.trim().isEmpty ? '(empty body)' : hint.trim()}');
  }
  Json payload;
  try {
    payload = jsonDecode(raw) as Json;
  } catch (_) {
    throw Exception('پاسخ سرور JSON نبود (احتمالاً خطای میزبان یا پروکسی). شروع پاسخ: ${raw.length > 160 ? raw.substring(0, 160) : raw}');
  }
  List<(String, String)> pairs(dynamic v, String a, String b) =>
      v is List ? v.map((e) => ('${(e as Json)[a]}', '${e[b]}')).toList() : [];
  return QuoteFetchResult(
    payload['quotes'] is List ? (payload['quotes'] as List).map((e) => ProviderQuote.fromJson(e as Json)).toList() : [],
    pairs(payload['failedProviders'], 'provider', 'error'),
    pairs(payload['unresolvedSlugs'], 'slug', 'reason'),
    payload['unknownRequestedSlugs'] is List ? (payload['unknownRequestedSlugs'] as List).map((e) => '$e').toList() : [],
  );
}

Future<List<ProviderQuote>> fetchProviderQuotes(List<String> slugs, [List<Json>? sources]) async =>
    (await fetchProviderQuotesDetailed(slugs, sources)).quotes;

// ─── Rate history store ────────────────────────────────────────────────────

Future<void> recordRateHistory(String userId, String currency, String dateString, double tomanPerUnit, String source) async {
  if (!(tomanPerUnit > 0)) return;
  try {
    if (source == 'provider') {
      final data = await sb
          .from('currency_rate_history')
          .select('source')
          .eq('user_id', userId)
          .eq('currency', currency)
          .eq('date_string', dateString)
          .maybeSingle();
      if (data != null && data['source'] == 'manual') return;
    }
    await sb.from('currency_rate_history').upsert({
      'user_id': userId,
      'currency': currency,
      'date_string': dateString,
      'toman_per_unit': tomanPerUnit,
      'source': source,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,currency,date_string');
  } catch (_) {}
}

Future<void> seedDerivedRateHistory(String userId, List<RateHistoryRow> rows) async {
  if (rows.isEmpty) return;
  try {
    final payload = rows
        .map((r) => {
              'user_id': userId,
              'currency': r.currency,
              'date_string': r.dateString,
              'toman_per_unit': r.tomanPerUnit,
              'source': 'derived',
            })
        .toList();
    for (var i = 0; i < payload.length; i += 500) {
      await sb
          .from('currency_rate_history')
          .upsert(payload.sublist(i, i + 500 > payload.length ? payload.length : i + 500),
              onConflict: 'user_id,currency,date_string', ignoreDuplicates: true);
    }
  } catch (_) {}
}

// ─── Persist ───────────────────────────────────────────────────────────────

Future<List<CurrencyRate>> persistCurrencyRate(String userId, String currency, double tomanPerUnit, {String source = 'provider'}) async {
  final data = await sb
      .from('currency_rates')
      .upsert([
        {'user_id': userId, 'currency': currency, 'toman_per_unit': tomanPerUnit, 'updated_at': DateTime.now().toUtc().toIso8601String()}
      ], onConflict: 'user_id,currency')
      .select();
  await recordRateHistory(userId, currency, formatJalaali(todayJalaaliTehran()), tomanPerUnit, source);
  return (data as List).map((e) => CurrencyRate.fromJson(e as Json)).toList();
}

class PersistResult {
  final List<Asset> assets;
  final List<DailyPrice> dailyPrices;
  PersistResult(this.assets, this.dailyPrices);
}

Future<PersistResult> persistProviderQuotes({
  required String userId,
  required List<Asset> assets,
  required List<DailyPrice> dailyPrices,
  required double usdRate,
  required List<ProviderQuote> quotes,
}) async {
  final bySlug = {for (final q in quotes) q.slug: q};
  final updates = assets.where((a) => a.priceSourceId != null && bySlug.containsKey(a.priceSourceId)).map((a) {
    final q = bySlug[a.priceSourceId]!;
    return {
      'id': a.id,
      'user_id': a.userId,
      'category_id': a.categoryId,
      'name': a.name,
      'unit': a.unit,
      'price_toman': q.priceToman,
      'price_usd': usdRate > 0 ? q.priceToman / usdRate : 0,
      'include_in_profit_loss': a.includeInProfitLoss,
      'include_in_balance': a.includeInBalance ?? true,
    };
  }).toList();
  if (updates.isEmpty) return PersistResult([], []);
  final assetRows = await sb.from('assets').upsert(updates).select();
  final today = todayStr();
  final snapshotByAsset = {for (final p in dailyPrices.where((p) => p.dateString == today)) p.assetId: p};
  final snapshotPayload = updates
      .where((u) {
        final e = snapshotByAsset[u['id']];
        return e == null || e.source == 'auto';
      })
      .map((u) => {
            'user_id': userId,
            'asset_id': u['id'],
            'date_string': today,
            'price_toman': u['price_toman'],
            'price_usd': u['price_usd'],
            'source': 'auto',
          })
      .toList();
  final assetsOut = (assetRows as List).map((e) => Asset.fromJson(e as Json)).toList();
  if (snapshotPayload.isEmpty) return PersistResult(assetsOut, []);
  final dpRows = await sb.from('daily_prices').upsert(snapshotPayload, onConflict: 'user_id,asset_id,date_string').select();
  return PersistResult(assetsOut, (dpRows as List).map((e) => DailyPrice.fromJson(e as Json)).toList());
}

List<T> mergeById<T>(List<T> prev, List<T> next, String Function(T) idOf) {
  if (next.isEmpty) return prev;
  final map = <String, T>{for (final i in prev) idOf(i): i};
  for (final i in next) {
    map[idOf(i)] = i;
  }
  return map.values.toList();
}

List<DailyPrice> mergeDailyPrices(List<DailyPrice> prev, List<DailyPrice> next) =>
    mergeById(prev, next, (p) => '${p.userId}|${p.assetId}|${p.dateString}');

List<CurrencyRate> mergeCurrencyRates(List<CurrencyRate> prev, List<CurrencyRate> next) => mergeById(prev, next, (r) => r.currency);
