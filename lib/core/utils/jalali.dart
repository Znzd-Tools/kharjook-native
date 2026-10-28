// Port of `jalaali-js` + `src/shared/utils/jalali.ts`.

import 'digits.dart';

class JDate {
  final int jy;
  final int jm; // 1–12
  final int jd; // 1–31
  const JDate(this.jy, this.jm, this.jd);

  @override
  bool operator ==(Object other) => other is JDate && other.jy == jy && other.jm == jm && other.jd == jd;
  @override
  int get hashCode => Object.hash(jy, jm, jd);
  JDate copyWith({int? jy, int? jm, int? jd}) => JDate(jy ?? this.jy, jm ?? this.jm, jd ?? this.jd);
}

class GDate {
  final int gy, gm, gd;
  const GDate(this.gy, this.gm, this.gd);
}

const kJalaliMonths = [
  'فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور',
  'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند',
];

const _breaks = [
  -61, 9, 38, 199, 426, 686, 756, 818, 1111, 1181, 1210, 1635, 2060, 2097, 2192, 2262, 2324, 2394, 2456, 3178,
];

int _div(int a, int b) => a ~/ b;
int _mod(int a, int b) => a - (a ~/ b) * b;

JDate toJalaali(int gy, int gm, int gd) => _d2j(_g2d(gy, gm, gd));
GDate toGregorian(int jy, int jm, int jd) => _d2g(_j2d(jy, jm, jd));

bool isValidJalaaliDate(int jy, int jm, int jd) =>
    jy >= -61 && jy <= 3177 && jm >= 1 && jm <= 12 && jd >= 1 && jd <= jalaaliMonthLength(jy, jm);

bool isLeapJalaaliYear(int jy) => _jalCalLeap(jy) == 0;

int jalaaliMonthLength(int jy, int jm) {
  if (jm <= 6) return 31;
  if (jm <= 11) return 30;
  if (isLeapJalaaliYear(jy)) return 30;
  return 29;
}

int _jalCalLeap(int jy) {
  final bl = _breaks.length;
  var jp = _breaks[0];
  var jump = 0;
  if (jy < jp || jy >= _breaks[bl - 1]) throw ArgumentError('Invalid Jalaali year $jy');
  for (var i = 1; i < bl; i += 1) {
    final jm = _breaks[i];
    jump = jm - jp;
    if (jy < jm) break;
    jp = jm;
  }
  var n = jy - jp;
  if (jump - n < 6) n = n - jump + _div(jump + 4, 33) * 33;
  var leap = _mod(_mod(n + 1, 33) - 1, 4);
  if (leap == -1) leap = 4;
  return leap;
}

class _JalCal {
  final int leap, gy, march;
  _JalCal(this.leap, this.gy, this.march);
}

_JalCal _jalCal(int jy, bool withoutLeap) {
  final bl = _breaks.length;
  final gy = jy + 621;
  var leapJ = -14;
  var jp = _breaks[0];
  var jump = 0;
  if (jy < jp || jy >= _breaks[bl - 1]) throw ArgumentError('Invalid Jalaali year $jy');
  for (var i = 1; i < bl; i += 1) {
    final jm = _breaks[i];
    jump = jm - jp;
    if (jy < jm) break;
    leapJ = leapJ + _div(jump, 33) * 8 + _div(_mod(jump, 33), 4);
    jp = jm;
  }
  var n = jy - jp;
  leapJ = leapJ + _div(n, 33) * 8 + _div(_mod(n, 33) + 3, 4);
  if (_mod(jump, 33) == 4 && jump - n == 4) leapJ += 1;
  final leapG = _div(gy, 4) - _div((_div(gy, 100) + 1) * 3, 4) - 150;
  final march = 20 + leapJ - leapG;
  if (withoutLeap) return _JalCal(0, gy, march);
  if (jump - n < 6) n = n - jump + _div(jump + 4, 33) * 33;
  var leap = _mod(_mod(n + 1, 33) - 1, 4);
  if (leap == -1) leap = 4;
  return _JalCal(leap, gy, march);
}

int _j2d(int jy, int jm, int jd) {
  final r = _jalCal(jy, true);
  return _g2d(r.gy, 3, r.march) + (jm - 1) * 31 - _div(jm, 7) * (jm - 7) + jd - 1;
}

JDate _d2j(int jdn) {
  final gy = _d2g(jdn).gy;
  var jy = gy - 621;
  final r = _jalCal(jy, false);
  final jdn1f = _g2d(gy, 3, r.march);
  var k = jdn - jdn1f;
  if (k >= 0) {
    if (k <= 185) {
      return JDate(jy, 1 + _div(k, 31), _mod(k, 31) + 1);
    } else {
      k -= 186;
    }
  } else {
    jy -= 1;
    k += 179;
    if (r.leap == 1) k += 1;
  }
  return JDate(jy, 7 + _div(k, 30), _mod(k, 30) + 1);
}

int _g2d(int gy, int gm, int gd) {
  var d = _div((gy + _div(gm - 8, 6) + 100100) * 1461, 4) + _div(153 * _mod(gm + 9, 12) + 2, 5) + gd - 34840408;
  d = d - _div(_div(gy + 100100 + _div(gm - 8, 6), 100) * 3, 4) + 752;
  return d;
}

GDate _d2g(int jdn) {
  var j = 4 * jdn + 139361631;
  j = j + _div(_div(4 * jdn + 183187720, 146097) * 3, 4) * 4 - 3908;
  final i = _div(_mod(j, 1461), 4) * 5 + 308;
  final gd = _div(_mod(i, 153), 5) + 1;
  final gm = _mod(_div(i, 153), 12) + 1;
  final gy = _div(j, 1461) - 100100 + _div(8 - gm, 6);
  return GDate(gy, gm, gd);
}

// ─── App wrapper (jalali.ts) ────────────────────────────────────────────────

JDate todayJalaali() {
  final now = DateTime.now();
  return toJalaali(now.year, now.month, now.day);
}

/// Jalali date in Asia/Tehran (UTC+3:30, no DST since 2022).
JDate todayJalaaliTehran() {
  final t = DateTime.now().toUtc().add(const Duration(hours: 3, minutes: 30));
  return toJalaali(t.year, t.month, t.day);
}

String formatJalaali(JDate d) => '${d.jy}/${d.jm.toString().padLeft(2, '0')}/${d.jd.toString().padLeft(2, '0')}';

String todayStr() => formatJalaali(todayJalaali());

JDate? parseJalaali(Object? input) {
  if (input == null) return null;
  final s = latinizeDigits(input.toString()).trim();
  final parts = s.split(RegExp(r'[-/]'));
  if (parts.length != 3) return null;
  final jy = int.tryParse(parts[0].trim());
  final jm = int.tryParse(parts[1].trim());
  final jd = int.tryParse(parts[2].trim());
  if (jy == null || jm == null || jd == null) return null;
  if (!isValidJalaaliDate(jy, jm, jd)) return null;
  return JDate(jy, jm, jd);
}

/// Shift a Jalali date by N days, Gregorian-accurate.
JDate addDays(JDate d, int days) {
  final g = toGregorian(d.jy, d.jm, d.jd);
  final dt = DateTime.utc(g.gy, g.gm, g.gd).add(Duration(days: days));
  return toJalaali(dt.year, dt.month, dt.day);
}

/// «۱ فروردین ۱۴۰۳»
String formatJalaaliHuman(JDate d) => '${toPersianDigits(d.jd)} ${kJalaliMonths[d.jm - 1]} ${toPersianDigits(d.jy)}';

/// 0 شنبه ... 6 جمعه
int jalaaliWeekday(JDate d) {
  final g = toGregorian(d.jy, d.jm, d.jd);
  final jsDay = DateTime.utc(g.gy, g.gm, g.gd).weekday % 7; // 0 Sun ... 6 Sat
  return (jsDay + 1) % 7;
}

const kWeekdayNames = ['شنبه', 'یکشنبه', 'دوشنبه', 'سه‌شنبه', 'چهارشنبه', 'پنجشنبه', 'جمعه'];

/// `parseDateToNumber` (parse-date.ts).
int parseDateToNumber(Object? dateStr) {
  if (dateStr == null) return 0;
  final normalized = latinizeDigits(dateStr.toString());
  if (normalized.isEmpty) return 0;
  final parts = normalized.split(RegExp(r'[-/_\s]'));
  if (parts.length >= 3) {
    final y = parts[0];
    final m = parts[1].padLeft(2, '0');
    final d = parts[2].padLeft(2, '0');
    return int.tryParse(y + m + d) ?? _leadingInt(y + m + d);
  }
  return int.tryParse(normalized.replaceAll(RegExp(r'\D'), '')) ?? 0;
}

int _leadingInt(String s) {
  final m = RegExp(r'^\s*-?\d+').firstMatch(s);
  return m == null ? 0 : int.parse(m.group(0)!.trim());
}

/// Days since 1970-01-01 (UTC) for a Jalali date string; null when invalid.
int? jalaliDayNumber(String date) {
  final p = parseJalaali(date);
  if (p == null) return null;
  final g = toGregorian(p.jy, p.jm, p.jd);
  return DateTime.utc(g.gy, g.gm, g.gd).millisecondsSinceEpoch ~/ 86400000;
}

/// Canonical Jalali date of an ISO timestamp in Tehran local day.
String? jalaliFromIso(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  final dt = DateTime.tryParse(iso);
  if (dt == null) return null;
  final t = dt.toUtc().add(const Duration(hours: 3, minutes: 30));
  return formatJalaali(toJalaali(t.year, t.month, t.day));
}

/// Jalali → Gregorian ISO date (YYYY-MM-DD).
String jalaliToIsoDate(JDate d) {
  final g = toGregorian(d.jy, d.jm, d.jd);
  return '${g.gy.toString().padLeft(4, '0')}-${g.gm.toString().padLeft(2, '0')}-${g.gd.toString().padLeft(2, '0')}';
}
