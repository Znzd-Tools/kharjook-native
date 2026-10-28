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
