// Ports of ImportTransactionsView.tsx, parse-transaction-csv.ts and
// import-transaction-payload.ts.

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../app/router.dart';
import '../../core/logic/ledger.dart';
import '../../core/logic/rate_history.dart';
import '../../core/models.dart';
import '../../core/services/api.dart';
import '../../core/services/files.dart';
import '../../core/store.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/toast.dart';
import '../../core/ui/widgets.dart';
import '../../core/utils/digits.dart';
import '../../core/utils/format.dart';
import '../../core/utils/jalali.dart';

const kTransactionCsvTemplate = '''date,type,amount,wallet,category,note
1403/04/15,expense,500000,ملی,خوراک,ناهار
1403/04/16,income,10000000,ملی,حقوق,
''';
const kMaxTransactionCsvRows = 200;

class ParsedCsvRow {
  final int lineNumber;
  final String date, type, walletName, categoryName, note;
  final double amountToman;
  ParsedCsvRow(this.lineNumber, this.date, this.type, this.amountToman, this.walletName, this.categoryName, this.note);
}

class ResolvedImportRow {
  final ParsedCsvRow row;
  final String walletId, categoryId;
  ResolvedImportRow(this.row, this.walletId, this.categoryId);
}

typedef CsvLineError = (int, String);

const _headerAliases = {
  'date': 'date',
  'تاریخ': 'date',
  'amount': 'amountToman',
  'مبلغ': 'amountToman',
  'wallet': 'walletName',
  'کیف': 'walletName',
  'کیف پول': 'walletName',
  'category': 'categoryName',
  'دسته': 'categoryName',
  'note': 'note',
  'یادداشت': 'note',
  'توضیح': 'note',
};

List<String> _parseCsvLine(String line) {
  final out = <String>[];
  final cur = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') {
      if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
        cur.write('"');
        i++;
      } else {
        inQuotes = !inQuotes;
      }
      continue;
    }
    if (ch == ',' && !inQuotes) {
      out.add(cur.toString().trim());
      cur.clear();
      continue;
    }
    cur.write(ch);
  }
  out.add(cur.toString().trim());
  return out;
}

String? _normalizeType(String raw) {
  final v = latinizeDigits(raw).trim().toLowerCase();
  if (const ['income', 'درآمد', 'inc'].contains(v)) return 'INCOME';
  if (const ['expense', 'هزینه', 'exp'].contains(v)) return 'EXPENSE';
  return null;
}

double? _parseAmount(String raw) {
  final cleaned = latinizeDigits(raw).replaceAll(RegExp(r'[,_\s]'), '');
  if (cleaned.isEmpty) return null; // Number('') is 0, which is rejected anyway.
  final v = double.tryParse(cleaned);
  if (v == null || !v.isFinite || v <= 0) return null;
  return v;
}

String? _normalizeDate(String raw) {
  final p = parseJalaali(latinizeDigits(raw).trim().replaceAll('-', '/'));
  return p == null ? null : formatJalaali(p);
}

Map<String, int>? _mapHeader(List<String> cells) {
  final lower = cells.map((c) => latinizeDigits(c).trim().toLowerCase()).toList();
  if (!lower.any((c) => _headerAliases.containsKey(c) || c == 'type' || c == 'نوع')) return null;
  final index = <String, int>{};
  for (var i = 0; i < lower.length; i++) {
    final c = lower[i];
    if (c == 'type' || c == 'نوع') {
      index['type'] = i;
      continue;
    }
    final m = _headerAliases[c];
    if (m != null) index[m] = i;
  }
  if (!['date', 'type', 'amountToman', 'walletName', 'categoryName'].every(index.containsKey)) return null;
  return index;
}

(List<ParsedCsvRow>, List<CsvLineError>) parseTransactionCsv(String text) {
  final errors = <CsvLineError>[];
  final rows = <ParsedCsvRow>[];
  final lines = text.replaceFirst(RegExp('^﻿'), '').split(RegExp(r'\r?\n')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  if (lines.isEmpty) return (rows, [(1, 'فایل خالی است.')]);
  final header = _mapHeader(_parseCsvLine(lines.first));
  final data = header != null ? lines.sublist(1) : lines;
  final startLine = header != null ? 2 : 1;
  const order = ['date', 'type', 'amountToman', 'walletName', 'categoryName', 'note'];
  String cell(List<String> cells, String key) {
    final idx = header != null ? header[key] : order.indexOf(key);
    return idx == null || idx < 0 || idx >= cells.length ? '' : cells[idx];
  }

  if (data.length > kMaxTransactionCsvRows) {
    return (rows, [(startLine, 'حداکثر $kMaxTransactionCsvRows ردیف مجاز است.')]);
  }
  for (var i = 0; i < data.length; i++) {
    final ln = startLine + i;
    final cells = _parseCsvLine(data[i]);
    final type = _normalizeType(cell(cells, 'type'));
    final amount = _parseAmount(cell(cells, 'amountToman'));
    final date = _normalizeDate(cell(cells, 'date'));
    final wallet = cell(cells, 'walletName').trim();
    final category = cell(cells, 'categoryName').trim();
    final note = cell(cells, 'note').trim();
    if (type == null) {
      errors.add((ln, 'نوع تراکنش نامعتبر است (income/expense).'));
    } else if (amount == null) {
      errors.add((ln, 'مبلغ نامعتبر است.'));
    } else if (date == null) {
      errors.add((ln, 'تاریخ نامعتبر است.'));
    } else if (wallet.isEmpty) {
      errors.add((ln, 'نام کیف پول خالی است.'));
    } else if (category.isEmpty) {
      errors.add((ln, 'نام دسته خالی است.'));
    } else {
      rows.add(ParsedCsvRow(ln, date, type, amount, wallet, category, note));
    }
  }
  return (rows, errors);
}

String _norm(String v) => v.trim().toLowerCase();

(List<ResolvedImportRow>, List<CsvLineError>) resolveImportRows(List<ParsedCsvRow> rows, List<Wallet> wallets, List<Category> categories) {
  final resolved = <ResolvedImportRow>[];
  final errors = <CsvLineError>[];
  for (final r in rows) {
    final t = _norm(r.walletName);
    final w = wallets.where((w) => _norm(w.name) == t).firstOrNull ?? wallets.where((w) => _norm(w.name).contains(t)).firstOrNull;
    if (w == null) {
      errors.add((r.lineNumber, 'کیف پول «${r.walletName}» پیدا نشد.'));
      continue;
    }
    final kind = r.type == 'INCOME' ? 'income' : 'expense';
    final ct = _norm(r.categoryName);
    final scoped = categories.where((c) => c.kind == kind);
    final c = scoped.where((c) => _norm(c.name) == ct).firstOrNull ?? scoped.where((c) => _norm(c.name).contains(ct)).firstOrNull;
    if (c == null) {
      errors.add((r.lineNumber, 'دسته «${r.categoryName}» برای ${r.type == 'INCOME' ? 'درآمد' : 'هزینه'} پیدا نشد.'));
      continue;
    }
    resolved.add(ResolvedImportRow(r, w.id, c.id));
  }
  return (resolved, errors);
}

Json? buildWalletImportPayload({
  required String userId,
  required String operationId,
  required ResolvedImportRow row,
  required Wallet wallet,
  required double usdRate,
  required List<CurrencyRate> currencyRates,
  RateHistories? histories,
  String? today,
}) {
  final r = row.row;
  final isPast = histories != null && today != null && r.date.compareTo(today) < 0;
  final histUsd = isPast ? histories['USD']?.at(r.date) : null;
  final usd = histUsd != null && histUsd > 0 ? histUsd : usdRate;
  if (!(usd > 0)) return null;
  var walletRate = tomanPerUnit(wallet.currency, currencyRates);
  if (isPast && wallet.currency != 'IRT') {
    final hist = wallet.currency == 'USD' ? usd : histories[wallet.currency]?.at(r.date);
    if (hist != null && hist > 0) walletRate = hist;
  }
  if (walletRate <= 0) return null;
  final walletAmount = wallet.currency == 'IRT' ? r.amountToman : r.amountToman / walletRate;
  final base = <String, dynamic>{
    'user_id': userId,
    'type': r.type,
    'date_string': r.date,
    'note': r.note.isEmpty ? null : r.note,
    'category_id': row.categoryId,
    'operation_id': operationId,
    'amount_toman_at_time': r.amountToman,
    'amount_usd_at_time': r.amountToman / usd,
    'asset_id': null,
    'amount': null,
    'price_toman': wallet.currency == 'IRT' ? null : walletRate,
    'usd_rate': wallet.currency == 'IRT' ? null : usd,
    'source_asset_id': null,
    'target_asset_id': null,
  };
  if (r.type == 'INCOME') {
    return {...base, 'target_wallet_id': wallet.id, 'target_amount': walletAmount, 'source_wallet_id': null, 'source_amount': null};
  }
  return {...base, 'source_wallet_id': wallet.id, 'source_amount': walletAmount, 'target_wallet_id': null, 'target_amount': null};
}

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});
  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  String? fileName;
  List<ParsedCsvRow> parsed = [];
  List<CsvLineError> parseErrors = [];
  bool importing = false;

  Future<void> _pick() async {
    try {
      final f = await FilePicker.pickFile(type: FileType.any);
      if (f == null) return;
      final text = await f.xFile.readAsString();
      final (rows, errors) = parseTransactionCsv(text);
      setState(() {
        fileName = f.name;
        parsed = rows;
        parseErrors = errors;
      });
    } catch (_) {
      Toast.error('خواندن فایل ناموفق بود.');
    }
  }

  Future<void> _import(PortfolioStore s, List<ResolvedImportRow> resolved, int errorCount) async {
    final user = s.user;
    if (user == null) {
      Toast.error('کاربر معتبر نیست.');
      return;
    }
    if (resolved.isEmpty) {
      Toast.error('ردیف معتبری برای ثبت نیست.');
      return;
    }
    if (errorCount > 0) {
      Toast.error('ابتدا خطاهای CSV را برطرف کنید.');
      return;
    }
    if (!(s.usdRate > 0)) {
      Toast.error('نرخ دلار ثبت نشده — از بخش قیمت‌ها نرخ را تنظیم کنید.');
      return;
    }
    final opId = const Uuid().v4();
    final today = todayStr();
    final payloads = <Json>[];
    for (final r in resolved) {
      final w = s.wallets.where((w) => w.id == r.walletId).firstOrNull;
      if (w == null) continue;
      final p = buildWalletImportPayload(userId: user.id, operationId: opId, row: r, wallet: w, usdRate: s.usdRate, currencyRates: s.currencyRates, histories: s.rateHistories, today: today);
      if (p != null) payloads.add(p);
    }
    if (payloads.isEmpty) {
      Toast.error('ساخت payload ناموفق بود.');
      return;
    }
    setState(() => importing = true);
    try {
      final data = await Supabase.instance.client.from('transactions').insert(payloads).select();
      final inserted = (data as List).cast<Json>().map(Transaction.fromJson).toList();
      s.update((st) => st.transactions = [...inserted, ...st.transactions]);
      Api.fireExpenseAlert(inserted.where((t) => t.type == 'EXPENSE').map((t) => t.id).toList());
      Toast.success('${toPersianDigits(inserted.length)} تراکنش ثبت شد.');
      if (mounted) Nav.replace(context, '/wallets');
    } catch (_) {
      Toast.error('خطا در ثبت دسته‌ای تراکنش‌ها.');
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<PortfolioStore>();
    final (resolved, resolveErrors) = resolveImportRows(parsed, s.wallets, s.categories);
    final errors = [...parseErrors, ...resolveErrors];
    return SubPage(
      title: 'ورود CSV تراکنش',
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'فایل CSV با ستون‌های '),
                const TextSpan(text: 'date,type,amount,wallet,category,note', style: TextStyle(color: C.purple300)),
                TextSpan(text: ' — فقط درآمد/هزینه کیف پول. حداکثر ${toPersianDigits(kMaxTransactionCsvRows)} ردیف.'),
              ]),
              style: const TextStyle(fontSize: 12, color: C.slate300, height: 1.7),
            ),
            const SizedBox(height: 6),
            const Text('مبلغ به تومان است. نام کیف و دسته باید با اپ یکی باشد. همه ردیف‌ها یک operation_id مشترک می‌گیرند.', style: TextStyle(fontSize: 11, color: C.slate500, height: 1.6)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: AppButton('دانلود نمونه', icon: Icons.download, variant: BtnVariant.secondary, dense: true, onPressed: () async {
                  try {
                    await shareTextFile('kharjook-transactions-template.csv', kTransactionCsvTemplate.trim());
                  } catch (_) {
                    Toast.error('خطا در ساخت فایل.');
                  }
                }),
              ),
              const SizedBox(width: 8),
              Expanded(child: AppButton('انتخاب فایل', icon: Icons.upload, dense: true, onPressed: _pick)),
            ]),
            if (fileName != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(children: [
                  const Icon(Icons.upload_file, size: 13, color: C.slate400),
                  const SizedBox(width: 4),
                  Expanded(child: Text(fileName!, style: const TextStyle(fontSize: 11, color: C.slate400))),
                ]),
              ),
          ]),
        ),
        if (errors.isNotEmpty) ...[
          const SizedBox(height: 12),
          AppCard(
            color: C.rose.withValues(alpha: 0.08),
            borderColor: C.rose.withValues(alpha: 0.3),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('خطاها', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: C.rose300)),
              const SizedBox(height: 6),
              for (final (ln, msg) in errors.take(8)) Text('ردیف ${toPersianDigits(ln)}: $msg', style: const TextStyle(fontSize: 11, color: C.rose300, height: 1.6)),
              if (errors.length > 8) Text('و ${errors.length - 8} خطای دیگر…', style: const TextStyle(fontSize: 11, color: C.rose300)),
            ]),
          ),
        ],
        if (resolved.isNotEmpty) ...[
          const SizedBox(height: 12),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const Expanded(child: Text('پیش‌نمایش', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white))),
                Text('${toPersianDigits(resolved.length)} ردیف', style: const TextStyle(fontSize: 11, color: C.slate400)),
              ]),
              const SizedBox(height: 8),
              for (final r in resolved.take(20))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${r.row.type == 'INCOME' ? 'درآمد' : 'هزینه'} · ${r.row.categoryName}', style: const TextStyle(fontSize: 12, color: C.slate200)),
                        Text('${r.row.date} · ${r.row.walletName}${r.row.note.isNotEmpty ? ' · ${r.row.note}' : ''}', style: const TextStyle(fontSize: 10, color: C.slate500)),
                      ]),
                    ),
                    Money(formatCurrency(r.row.amountToman, 'TOMAN'),
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: r.row.type == 'INCOME' ? const Color(0xFF34D399) : const Color(0xFFFB7185))),
                  ]),
                ),
              if (resolved.length > 20) Text('… و ${toPersianDigits(resolved.length - 20)} ردیف دیگر', style: const TextStyle(fontSize: 11, color: C.slate500)),
            ]),
          ),
        ],
        const SizedBox(height: 16),
        AppButton(
          importing ? 'در حال ثبت…' : 'ثبت ${toPersianDigits(resolved.length)} تراکنش',
          expand: true,
          onPressed: importing || resolved.isEmpty || errors.isNotEmpty ? null : () => _import(s, resolved, errors.length),
        ),
      ]),
    );
  }
}
