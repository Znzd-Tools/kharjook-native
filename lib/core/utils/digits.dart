const _persian = '۰۱۲۳۴۵۶۷۸۹';
const _arabic = '٠١٢٣٤٥٦٧٨٩';

String toPersianDigits(Object value) =>
    value.toString().replaceAllMapped(RegExp(r'\d'), (m) => _persian[int.parse(m.group(0)!)]);

/// Persian / Arabic-Indic digits (and Arabic decimal mark) → ASCII.
String latinizeDigits(Object? input) {
  if (input == null) return '';
  final s = input.toString().replaceAll('٫', '.');
  final out = StringBuffer();
  for (final ch in s.split('')) {
    final pi = _persian.indexOf(ch);
    if (pi != -1) {
      out.write(pi);
      continue;
    }
    final ai = _arabic.indexOf(ch);
    if (ai != -1) {
      out.write(ai);
      continue;
    }
    out.write(ch);
  }
  return out.toString();
}

const _faOrder = 'آاأإبپتثجچحخدذرزژسشصضطظعغفقکكگلمنوؤهةیيئ';

/// Approximates `a.localeCompare(b, 'fa')`: Persian alphabet order, then code units.
int faCompare(String a, String b) {
  final n = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    final ca = a[i], cb = b[i];
    if (ca == cb) continue;
    final ia = _faOrder.indexOf(ca), ib = _faOrder.indexOf(cb);
    if (ia != -1 && ib != -1) return ia - ib;
    if (ia != -1) return 1; // Latin/digits sort before Persian letters
    if (ib != -1) return -1;
    return ca.toLowerCase().compareTo(cb.toLowerCase());
  }
  return a.length - b.length;
}
