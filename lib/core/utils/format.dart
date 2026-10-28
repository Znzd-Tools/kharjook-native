// Ports of format-currency.ts, format-display-number.ts, format-asset-amount.ts,
// format-number-input.ts.

import 'digits.dart';

String _group(String intDigits) {
  final buf = StringBuffer();
  for (var i = 0; i < intDigits.length; i++) {
    if (i > 0 && (intDigits.length - i) % 3 == 0) buf.write(',');
    buf.write(intDigits[i]);
  }
  return buf.toString();
}

/// JS `value.toLocaleString('en-US', {minimumFractionDigits, maximumFractionDigits})`.
/// Default max = max(min, 3) like Intl.
String formatEnNumber(double value, {int? minFrac, int? maxFrac, bool grouping = true}) {
  if (value.isNaN) return 'NaN';
  if (value.isInfinite) return value > 0 ? '∞' : '-∞';
  final minF = minFrac ?? 0;
  var maxF = maxFrac ?? (minF > 3 ? minF : 3);
  if (maxF < minF) maxF = minF;
  if (maxF > 20) maxF = 20;
  final neg = value < 0;
  var fixed = value.abs().toStringAsFixed(maxF);
  var intPart = fixed;
  var frac = '';
  final dot = fixed.indexOf('.');
  if (dot != -1) {
    intPart = fixed.substring(0, dot);
    frac = fixed.substring(dot + 1);
  }
  // Trim trailing zeros down to minF.
  while (frac.length > minF && frac.endsWith('0')) {
    frac = frac.substring(0, frac.length - 1);
  }
  final isZero = RegExp(r'^0*$').hasMatch(intPart) && RegExp(r'^0*$').hasMatch(frac);
  final grouped = grouping ? _group(intPart) : intPart;
  final sign = neg && !isZero ? '-' : '';
  return frac.isEmpty ? '$sign$grouped' : '$sign$grouped.$frac';
}

int currencyFractionDigits(String currency) {
  if (currency == 'USD') return 2;
  if (currency == 'IRT' || currency == 'TOMAN') return 0;
  return 2;
}

String formatCurrencyAmount(num? value, String currency) {
  final d = currencyFractionDigits(currency);
  return formatEnNumber((value ?? 0).toDouble(), minFrac: d, maxFrac: d);
}

/// `formatCurrency` — `$1,234.50` or `1,234 ت`.
String formatCurrency(num? value, String currency) {
  if (value == null) {
    final zero = formatCurrencyAmount(0, currency);
    return currency == 'USD' ? '\$$zero' : '$zero ت';
  }
  final v = value.toDouble();
  final formatted = formatCurrencyAmount(v.abs(), currency);
  final sign = v < 0 ? '-' : '';
  return currency == 'USD' ? '$sign\$$formatted' : '$sign$formatted ت';
}

/// Signed variant used on P/L figures: `+1,000 ت`.
String formatSignedCurrency(num value, String currency) =>
    '${value > 0 ? '+' : ''}${formatCurrency(value, currency)}';

/// Wallet-native amount, e.g. `12.50 USD` / `1,000 ت`.
String formatWalletAmount(num value, String currency) {
  if (currency == 'IRT') return formatCurrency(value, 'TOMAN');
  if (currency == 'USD') return formatCurrency(value, 'USD');
  return '${formatCurrencyAmount(value, currency)} $currency';
}

String formatDisplayNumber(num value, {bool persian = true, bool grouping = true, int? maximumFractionDigits, int? minimumFractionDigits}) {
  final v = value.toDouble();
  if (v.isNaN || v.isInfinite) return persian ? '۰' : '0';
  final formatted = grouping
      ? formatEnNumber(v, minFrac: minimumFractionDigits, maxFrac: maximumFractionDigits)
      : _jsString(v);
  return persian ? toPersianDigits(formatted) : formatted;
}

String _jsString(double v) {
  if (v == v.truncateToDouble() && v.abs() < 1e21) return v.toInt().toString();
  return v.toString();
}

/// JS `x.toFixed(n)`.
String toFixed(num v, int n) => v.toDouble().toStringAsFixed(n);

String formatPercent(num v, {int digits = 1}) => '${toFixed(v, digits)}%';

// ─── Asset amounts ─────────────────────────────────────────────────────────

int normalizeAssetDecimals(Object? value) {
  final n = value is num ? value.toDouble() : double.tryParse('$value');
  if (n == null || n.isNaN || n.isInfinite) return 4;
  final i = n.truncate();
  return i < 0 ? 0 : (i > 12 ? 12 : i);
}

/// Truncating (never shows more than is held) on the decimal string.
String formatAssetAmount(num? value, int decimals) {
  final safe = (value ?? 0).toDouble();
  if (safe.isNaN || safe.isInfinite) return '0';
  final places = normalizeAssetDecimals(decimals);
  final guard = (places + 6) > 15 ? 15 : places + 6;
  final fixed = safe.abs().toStringAsFixed(guard);
  final parts = fixed.split('.');
  final intRaw = parts[0];
  var frac = parts.length > 1 ? parts[1] : '';
  frac = frac.substring(0, places > frac.length ? frac.length : places).replaceAll(RegExp(r'0+$'), '');
  final isZero = RegExp(r'^0*$').hasMatch(intRaw) && frac.isEmpty;
  final sign = safe < 0 && !isZero ? '-' : '';
  final intPart = _group(BigInt.parse(intRaw).toString());
  return frac.isNotEmpty ? '$sign$intPart.$frac' : '$sign$intPart';
}

// ─── Numeric input ─────────────────────────────────────────────────────────

String parseFormattedNumberToCanonical(String input) {
  final normalized = latinizeDigits(input.replaceAll(RegExp(r'[,\s ٬]'), ''));
  final out = StringBuffer();
  var dotSeen = false;
  for (final ch in normalized.split('')) {
    if (ch == '.') {
      if (!dotSeen) {
        out.write(ch);
        dotSeen = true;
      }
      continue;
    }
    if (ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57) out.write(ch);
  }
  return out.toString();
}

String formatCanonicalNumberDisplay(String canonical) {
  if (canonical.isEmpty) return '';
  final endsWithBareDot = canonical.endsWith('.') && canonical.split('.').length <= 2;
  final core = endsWithBareDot ? canonical.substring(0, canonical.length - 1) : canonical;
  final dotIdx = core.indexOf('.');
  final intRaw = dotIdx == -1 ? core : core.substring(0, dotIdx);
  final fracRaw = dotIdx == -1 ? '' : core.substring(dotIdx + 1);
  String intFormatted;
  if (intRaw.isEmpty) {
    intFormatted = '0';
  } else {
    final normalized = intRaw.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    intFormatted = _group(BigInt.parse(normalized.isEmpty ? '0' : normalized).toString());
  }
  if (fracRaw.isEmpty && !endsWithBareDot) return intFormatted;
  if (fracRaw.isEmpty && endsWithBareDot) return '$intFormatted.';
  return '$intFormatted.$fracRaw';
}

/// Canonical string for prefilling an input from a number (no exponent).
String numberToCanonical(num? v, {int maxFrac = 12}) {
  if (v == null || v.isNaN || v.isInfinite) return '';
  var s = v.toDouble().toStringAsFixed(maxFrac);
  if (s.contains('.')) {
    s = s.replaceAll(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  }
  if (s.startsWith('-')) s = s.substring(1);
  return s;
}

/// JS `Number(canonical)`: '' → 0, invalid → NaN.
double canonicalToNumber(String s) {
  if (s.trim().isEmpty) return 0;
  return double.tryParse(s) ?? double.nan;
}

String formatCardNumber(String digits) {
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && i % 4 == 0) buf.write('-');
    buf.write(digits[i]);
  }
  return buf.toString();
}
