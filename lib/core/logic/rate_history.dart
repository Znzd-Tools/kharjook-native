// Port of rate-history.ts — historical Toman rates rebuilt from the user's data.

import '../models.dart';
import '../utils/jalali.dart';

class RatePoint {
  final int day;
  final String date;
  final double rate;
  RatePoint(this.day, this.date, this.rate);
}

class RateHistoryRow {
  final String currency;
  final String dateString;
  final double tomanPerUnit;
  RateHistoryRow(this.currency, this.dateString, this.tomanPerUnit);
  factory RateHistoryRow.fromJson(Json j) =>
      RateHistoryRow(j['currency'] as String, j['date_string'] as String, numOr0(j['toman_per_unit']));
}

class _Obs {
  final int day;
  final String date;
  final double rate;
  final int tier;
  _Obs(this.day, this.date, this.rate, this.tier);
}

class RateHistory {
  final List<RatePoint> points;
  RateHistory(this.points);

  double? at(String date) {
    if (points.isEmpty) return null;
    final day = jalaliDayNumber(date);
    if (day == null) return points.last.rate;
    if (day <= points.first.day) return points.first.rate;
    final last = points.last;
    if (day >= last.day) return last.rate;
    var lo = 0;
    var hi = points.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (points[mid].day < day) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final next = points[lo];
    if (next.day == day) return next.rate;
    final prev = points[lo - 1];
    final t = (day - prev.day) / (next.day - prev.day);
    return prev.rate + (next.rate - prev.rate) * t;
  }

  double? latest() => points.isEmpty ? null : points.last.rate;
}

typedef RateHistories = Map<String, RateHistory>;

const _lateEntryDays = 3;
const _outlierWindowDays = 30;

double _median(List<double> values) {
  final s = [...values]..sort();
  final mid = s.length ~/ 2;
  return s.length.isOdd ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}

String? _canonical(String date) {
  final p = parseJalaali(date);
  return p == null ? null : formatJalaali(p);
}

int? _isoDayNumber(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  final dt = DateTime.tryParse(iso);
  if (dt == null) return null;
  return (dt.millisecondsSinceEpoch + 3.5 * 3600000) ~/ 86400000;
}

RateHistory _historyFromObservations(List<_Obs> obs) {
  final byDay = <int, List<_Obs>>{};
  for (final o in obs) {
    if (!(o.rate > 0) || !o.rate.isFinite) continue;
    byDay.putIfAbsent(o.day, () => []).add(o);
  }
  var points = <RatePoint>[];
  byDay.forEach((day, list) {
    final best = list.map((o) => o.tier).reduce((a, b) => a < b ? a : b);
    final chosen = list.where((o) => o.tier == best).toList();
    points.add(RatePoint(day, chosen.first.date, _median(chosen.map((o) => o.rate).toList())));
  });
  points.sort((a, b) => a.day - b.day);

  if (points.length >= 4) {
    final src = points;
    final keep = <RatePoint>[];
    var lo = 0;
    var hi = 0;
    for (var idx = 0; idx < src.length; idx += 1) {
      final p = src[idx];
      while (src[lo].day < p.day - _outlierWindowDays) {
        lo += 1;
      }
      while (hi + 1 < src.length && src[hi + 1].day <= p.day + _outlierWindowDays) {
        hi += 1;
      }
      final neighbours = <double>[];
      for (var k = lo; k <= hi; k += 1) {
        if (k != idx) neighbours.add(src[k].rate);
      }
      if (neighbours.length < 3) {
        keep.add(p);
        continue;
      }
      final m = _median(neighbours);
      if (p.rate >= m / 2 && p.rate <= m * 2) keep.add(p);
    }
    points = keep;
  }
  return RateHistory(points);
}

bool _hasAssetLeg(Transaction tx) => tx.assetId != null || tx.sourceAssetId != null || tx.targetAssetId != null;

Map<String, List<_Obs>> _collect({
  required List<Transaction> transactions,
  List<DailyPrice> dailyPrices = const [],
  List<CurrencyRate> currencyRates = const [],
  List<Wallet> wallets = const [],
  List<RateHistoryRow> savedHistory = const [],
}) {
  final out = <String, List<_Obs>>{'USD': [], 'TRY': [], 'EUR': []};
  void push(String currency, String date, double rate, int tier) {
    final c = _canonical(date);
    if (c == null || !(rate > 0) || !rate.isFinite) return;
    final day = jalaliDayNumber(c);
    if (day == null) return;
    out[currency]?.add(_Obs(day, c, rate, tier));
  }

  for (final row in savedHistory) {
    if (out.containsKey(row.currency)) push(row.currency, row.dateString, row.tomanPerUnit, 0);
  }
  for (final r in currencyRates) {
    final date = jalaliFromIso(r.updatedAt);
    if (date != null && out.containsKey(r.currency)) push(r.currency, date, r.tomanPerUnit, 1);
  }
  for (final p in dailyPrices) {
    if (p.source == 'trade') continue;
    if (p.priceToman > 0 && p.priceUsd > 0) push('USD', p.dateString, p.priceToman / p.priceUsd, 2);
  }
  final walletById = {for (final w in wallets) w.id: w};
  for (final tx in transactions) {
    final day = jalaliDayNumber(tx.dateString);
    if (day == null) continue;
    final created = _isoDayNumber(tx.createdAt);
    final late = created != null && created - day > _lateEntryDays;
    final isTrade = tx.type == 'BUY' || tx.type == 'SELL' || tx.type == 'TRANSFER';
    if (!isTrade && late) continue;
    final tier = isTrade ? (late ? 5 : 3) : 4;
    final usdRate = tx.usdRate ?? 0;
    if (usdRate > 0) {
      push('USD', tx.dateString, usdRate, tier);
    } else {
      final t = tx.amountTomanAtTime ?? 0;
      final u = tx.amountUsdAtTime ?? 0;
      if (t > 0 && u > 0) push('USD', tx.dateString, t / u, tier);
    }
    if (!_hasAssetLeg(tx)) {
      final wallet = walletById[tx.sourceWalletId ?? ''] ?? walletById[tx.targetWalletId ?? ''];
      final price = tx.priceToman ?? 0;
      if (wallet != null && wallet.currency != 'IRT' && price > 0) push(wallet.currency, tx.dateString, price, tier);
    }
  }
  return out;
}

RateHistories buildRateHistories({
  required List<Transaction> transactions,
  List<DailyPrice> dailyPrices = const [],
  List<CurrencyRate> currencyRates = const [],
  List<Wallet> wallets = const [],
  List<RateHistoryRow> savedHistory = const [],
}) {
  final obs = _collect(
    transactions: transactions,
    dailyPrices: dailyPrices,
    currencyRates: currencyRates,
    wallets: wallets,
    savedHistory: savedHistory,
  );
  return {
    'USD': _historyFromObservations(obs['USD']!),
    'TRY': _historyFromObservations(obs['TRY']!),
    'EUR': _historyFromObservations(obs['EUR']!),
  };
}

final _txUsdCache = Expando<RateHistory>();

/// USD history from transactions only, cached per list instance.
RateHistory usdHistoryFromTransactions(List<Transaction> transactions) {
  final hit = _txUsdCache[transactions];
  if (hit != null) return hit;
  final h = _historyFromObservations(_collect(transactions: transactions)['USD']!);
  _txUsdCache[transactions] = h;
  return h;
}

List<RateHistoryRow> derivedHistoryRows(RateHistories histories) {
  final rows = <RateHistoryRow>[];
  histories.forEach((currency, h) {
    for (final p in h.points) {
      rows.add(RateHistoryRow(currency, p.date, p.rate));
    }
  });
  return rows;
}
