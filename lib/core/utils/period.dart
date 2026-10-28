// Port of period.ts — Jalali period math.

import 'digits.dart';
import 'jalali.dart';

const kPeriodKinds = ['day', 'week', 'month', 'year', 'all'];
const _allStart = JDate(1300, 1, 1);

class Period {
  final String kind; // day | week | month | year | all
  final JDate start; // inclusive
  final JDate end; // inclusive
  const Period(this.kind, this.start, this.end);
  Period withEnd(JDate e) => Period(kind, start, e);
}

int jalaaliToNumber(JDate d) => d.jy * 10000 + d.jm * 100 + d.jd;
int cmpJalaali(JDate a, JDate b) => jalaaliToNumber(a) - jalaaliToNumber(b);

JDate startOfWeek(JDate d) => addDays(d, -jalaaliWeekday(d));

Period periodContaining(String kind, JDate d) {
  switch (kind) {
    case 'day':
      return Period(kind, d, d);
    case 'week':
      final start = startOfWeek(d);
      return Period(kind, start, addDays(start, 6));
    case 'month':
      return Period(kind, JDate(d.jy, d.jm, 1), JDate(d.jy, d.jm, jalaaliMonthLength(d.jy, d.jm)));
    case 'year':
      return Period(kind, JDate(d.jy, 1, 1), JDate(d.jy, 12, jalaaliMonthLength(d.jy, 12)));
    default:
      return Period('all', _allStart, todayJalaali());
  }
}

Period currentPeriod(String kind) => periodContaining(kind, todayJalaali());

Period shiftPeriod(Period p, int delta) {
  if (delta == 0) return p;
  switch (p.kind) {
    case 'day':
      return periodContaining('day', addDays(p.start, delta));
    case 'week':
      return periodContaining('week', addDays(p.start, delta * 7));
    case 'month':
      final total = p.start.jm - 1 + delta;
      final jy = p.start.jy + (total / 12).floor();
      final jm = ((total % 12) + 12) % 12 + 1;
      return periodContaining('month', JDate(jy, jm, 1));
    case 'year':
      return periodContaining('year', JDate(p.start.jy + delta, 1, 1));
    default:
      return p;
  }
}

bool isCurrentPeriod(Period p) {
  final t = todayJalaali();
  return cmpJalaali(t, p.start) >= 0 && cmpJalaali(t, p.end) <= 0;
}

Period clampPeriodToToday(Period p) {
  final t = todayJalaali();
  return cmpJalaali(p.end, t) > 0 ? p.withEnd(t) : p;
}

bool isInPeriod(String dateString, Period p) {
  final parsed = parseJalaali(dateString);
  if (parsed == null) return false;
  final n = jalaaliToNumber(parsed);
  return n >= jalaaliToNumber(p.start) && n <= jalaaliToNumber(p.end);
}

String formatPeriodLabel(Period p) {
  switch (p.kind) {
    case 'day':
      return formatJalaaliHuman(p.start);
    case 'week':
      if (p.start.jy == p.end.jy && p.start.jm == p.end.jm) {
        return '${toPersianDigits(p.start.jd)} تا ${toPersianDigits(p.end.jd)} ${kJalaliMonths[p.start.jm - 1]} ${toPersianDigits(p.start.jy)}';
      }
      return '${formatJalaaliHuman(p.start)} تا ${formatJalaaliHuman(p.end)}';
    case 'month':
      return '${kJalaliMonths[p.start.jm - 1]} ${toPersianDigits(p.start.jy)}';
    case 'year':
      return 'سال ${toPersianDigits(p.start.jy)}';
    default:
      return 'از ابتدا';
  }
}

String formatPeriodKindLabel(String kind) => const {
      'day': 'روز',
      'week': 'هفته',
      'month': 'ماه',
      'year': 'سال',
      'all': 'از ابتدا',
    }[kind]!;

String formatCurrentPeriodLabel(String kind) => const {
      'day': 'امروز',
      'week': 'این هفته',
      'month': 'این ماه',
      'year': 'امسال',
      'all': 'از ابتدا',
    }[kind]!;

/// Same calendar slice in the prior month/year (period-comparison.ts).
Period? matchingPriorPeriod(Period period) {
  if (period.kind == 'all' || period.kind == 'day' || period.kind == 'week') return null;
  if (period.kind == 'month') {
    final prevStart = shiftPeriod(period, -1).start;
    final len = jalaaliMonthLength(prevStart.jy, prevStart.jm);
    final endDay = period.end.jd < len ? period.end.jd : len;
    return Period('month', prevStart, JDate(prevStart.jy, prevStart.jm, endDay));
  }
  final prevYear = period.start.jy - 1;
  final len = jalaaliMonthLength(prevYear, period.end.jm);
  final endDay = period.end.jd < len ? period.end.jd : len;
  return Period('year', JDate(prevYear, 1, 1), JDate(prevYear, period.end.jm, endDay));
}

double? percentChange(double current, double previous) {
  if (previous == 0) {
    if (current == 0) return 0;
    return null;
  }
  return ((current - previous) / previous.abs()) * 100;
}

String priorPeriodCompareLabel(String kind) {
  if (kind == 'month') return 'نسبت به ماه قبل (هم‌تراز)';
  if (kind == 'year') return 'نسبت به سال قبل (هم‌تراز)';
  return '';
}
