// Ports of ExpensePlanView.tsx and plan/utils/build-plan-suggestions.ts.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/logic/domain_utils.dart';
import '../../core/logic/ledger.dart';
import '../../core/models.dart';
import '../../core/store.dart';
import '../../core/ui/category_picker.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/toast.dart';
import '../../core/ui/widgets.dart';
import '../../core/utils/format.dart';
import '../../core/utils/jalali.dart';
import '../../core/utils/period.dart';
import '../reports/report_logic.dart';
import '../transactions/tx_logic.dart';

const _sourceLabels = {'installment': 'قسط', 'recurring': 'دوره‌ای', 'check': 'چک', 'subscription': 'اشتراک'};

class PlanSuggestion {
  final String key, sourceType, sourceId, title;
  final String? subtitle, categoryId, note;
  final double amountToman;
  PlanSuggestion(this.key, this.sourceType, this.sourceId, this.title, this.subtitle, this.amountToman, this.categoryId, this.note);
}

double _toToman(double amount, String currency, List<CurrencyRate> rates) {
  final r = tomanPerUnit(currency, rates);
  return r > 0 ? amount * r : 0;
}

List<PlanSuggestion> buildPlanSuggestions({
  required Period period,
  required List<ExpensePlanItem> items,
  required List<LoanInstallment> installments,
  required List<Loan> loans,
  required List<Check> checks,
  required List<RecurringTransaction> recurring,
  required List<Subscription> subscriptions,
  required List<CurrencyRate> currencyRates,
  List<Asset> assets = const [],
}) {
  bool added(String type, String id) => items.any((i) => i.sourceType == type && i.sourceId == id);
  final loansById = {for (final l in loans) l.id: l};
  final assetsById = {for (final a in assets) a.id: a};
  final inst = <(String, PlanSuggestion)>[];
  final out = <PlanSuggestion>[];

  for (final i in installments) {
    if (i.isPaid) continue;
    final remaining = installmentRemainingAmount(i);
    if (remaining <= 0) continue;
    final loan = loansById[i.loanId];
    if (loan == null || added('installment', i.id)) continue;
    final t = loanAmountToToman(remaining, loan.currency, loan.assetId, currencyRates, assetsById);
    if (t <= 0) continue;
    inst.add((i.dueDateString, PlanSuggestion('installment:${i.id}', 'installment', i.id, loan.title, 'قسط ${i.sequenceNo} · ${i.dueDateString}', t, loan.categoryId, i.note)));
  }
  for (final c in checks) {
    if (c.status != 'pending' || c.deletedAt != null || added('check', c.id)) continue;
    final t = _toToman(c.amount, c.currency, currencyRates);
    if (t <= 0) continue;
    out.add(PlanSuggestion('check:${c.id}', 'check', c.id, c.title, c.dueDateString, t, c.categoryId, c.note));
  }
  for (final r in recurring) {
    if (r.type != 'EXPENSE') continue;
    final dues = recurringDueDatesInPeriod(r, period);
    if (dues.isEmpty || added('recurring', r.id)) continue;
    final t = r.amountToman * dues.length;
    if (t <= 0) continue;
    out.add(PlanSuggestion('recurring:${r.id}', 'recurring', r.id, r.title, dues.length == 1 ? dues.first : '${dues.length} بار در این ماه', t, r.categoryId, r.note));
  }
  for (final s in subscriptions) {
    if (s.status != 'active' || s.deletedAt != null) continue;
    final dues = subscriptionDueDatesInPeriod(s, period);
    if (dues.isEmpty || added('subscription', s.id)) continue;
    final t = _toToman(s.amount, s.currency, currencyRates) * dues.length;
    if (t <= 0) continue;
    out.add(PlanSuggestion('subscription:${s.id}', 'subscription', s.id, s.platform, dues.length == 1 ? dues.first : '${dues.length} بار در این ماه', t, s.categoryId, s.note));
  }
  return [
    ...stableSorted(inst, (a, b) => a.$1.compareTo(b.$1)).map((e) => e.$2),
    ...stableSorted(out, (a, b) => (b.amountToman - a.amountToman).sign.toInt()),
  ];
}

double? _toPositive(String v) {
  final s = v.trim().replaceAll(',', '');
  if (s.isEmpty) return null;
  final x = n(s);
  return x.isFinite && x > 0 ? x : null;
}

class ExpensePlanScreen extends StatefulWidget {
  const ExpensePlanScreen({super.key});
  @override
  State<ExpensePlanScreen> createState() => _ExpensePlanScreenState();
}

class _ExpensePlanScreenState extends State<ExpensePlanScreen> {
  Period target = shiftPeriod(currentPeriod('month'), 1);
  List<ExpensePlanItem> items = [];
  List<LoanInstallment> installments = [];
  List<Loan> loans = [];
  List<Check> checks = [];
  List<RecurringTransaction> recurring = [];
  List<Subscription> subscriptions = [];
  List<CategorySpendingCap> caps = [];
  bool loading = true, submitting = false;
  final Set<String> pending = {};
  int _req = 0;

  SupabaseClient get _c => Supabase.instance.client;
  String get monthKey => formatJalaali(target.start);

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final req = ++_req;
    setState(() => loading = true);
    try {
      final r = await Future.wait([
        _c.from('expense_plan_items').select().eq('month_start_string', monthKey).order('sort_order', ascending: true).order('created_at', ascending: true),
        _c.from('loans').select().isFilter('deleted_at', null),
        _c.from('loan_installments').select().order('due_date_string', ascending: true).order('sequence_no', ascending: true),
        _c.from('checks').select().isFilter('deleted_at', null),
        _c.from('recurring_transactions').select().isFilter('deleted_at', null).eq('is_active', true),
        _c.from('subscriptions').select().isFilter('deleted_at', null).eq('status', 'active'),
        _c.from('category_spending_caps').select(),
      ]);
      if (req != _req) return;
      List<T> m<T>(int i, T Function(Json) f) => (r[i] as List).cast<Json>().map(f).toList();
      items = m(0, ExpensePlanItem.fromJson);
      loans = m(1, Loan.fromJson);
      installments = m(2, LoanInstallment.fromJson);
      checks = m(3, Check.fromJson);
      recurring = m(4, RecurringTransaction.fromJson);
      subscriptions = m(5, Subscription.fromJson);
      caps = m(6, CategorySpendingCap.fromJson);
    } catch (_) {
      if (req == _req) Toast.error('خطا در دریافت برنامه هزینه.');
    } finally {
      if (mounted && req == _req) setState(() => loading = false);
    }
  }

  void _shift(int d) {
    setState(() => target = shiftPeriod(target, d));
    _refresh();
  }

  int get _nextSort => items.isEmpty ? 0 : items.map((i) => i.sortOrder).reduce((a, b) => a > b ? a : b) + 1;

  Future<void> _insert(PortfolioStore s, {required String title, required double amount, String? categoryId, String? note, required String sourceType, String? sourceId}) async {
    final user = s.user;
    if (user == null) return;
    final tempId = 'temp-plan-${const Uuid().v4()}';
    final snapshot = items;
    final sort = _nextSort;
    setState(() {
      submitting = true;
      pending.add(tempId);
      items = [
        ...items,
        ExpensePlanItem(id: tempId, userId: user.id, monthStartString: monthKey, title: title, amountToman: amount, categoryId: categoryId, note: note, sourceType: sourceType, sourceId: sourceId, sortOrder: sort),
      ];
    });
    try {
      final data = await _c
          .from('expense_plan_items')
          .insert({
            'user_id': user.id,
            'month_start_string': monthKey,
            'title': title,
            'amount_toman': amount,
            'category_id': categoryId,
            'note': note,
            'source_type': sourceType,
            'source_id': sourceId,
            'sort_order': sort,
          })
          .select()
          .single();
      final saved = ExpensePlanItem.fromJson(data);
      setState(() => items = [for (final i in items) i.id == tempId ? saved : i]);
    } catch (_) {
      setState(() => items = snapshot);
      Toast.error('ثبت آیتم برنامه ناموفق بود.');
    } finally {
      if (mounted) {
        setState(() {
          pending.remove(tempId);
          submitting = false;
        });
      }
    }
  }

  Future<void> _delete(String id) async {
    final snapshot = items;
    setState(() {
      submitting = true;
      pending.add(id);
      items = items.where((i) => i.id != id).toList();
    });
    try {
      await _c.from('expense_plan_items').delete().eq('id', id);
    } catch (_) {
      setState(() => items = snapshot);
      Toast.error('حذف آیتم ناموفق بود.');
    } finally {
      if (mounted) {
        setState(() {
          pending.remove(id);
          submitting = false;
        });
      }
    }
  }

  Future<void> _openManual(PortfolioStore s, [ExpensePlanItem? editing]) async {
    var title = editing?.title ?? '', amount = editing != null ? jsNumStr(editing.amountToman) : '', note = editing?.note ?? '';
    String? categoryId = editing?.categoryId;
    await showAppSheet(context, title: editing != null ? 'ویرایش آیتم' : 'آیتم جدید', builder: (ctx) {
      return StatefulBuilder(builder: (ctx, setSt) {
        final canSubmit = title.trim().isNotEmpty && _toPositive(amount) != null;
        final cat = categoryId == null ? null : s.categories.where((c) => c.id == categoryId && c.kind == 'expense').firstOrNull;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Field(label: 'عنوان', child: AppTextField(value: title, autofocus: true, hint: 'مثلاً خرید هفتگی، شهریه کلاس …', onChanged: (v) => setSt(() => title = v))),
          Field(label: 'مبلغ (تومان)', child: NumberInput(value: amount, hint: '۰', onChanged: (v) => setSt(() => amount = v))),
          Field(label: 'یادداشت (اختیاری)', child: AppTextField(value: note, maxLines: 2, hint: 'توضیح کوتاه …', onChanged: (v) => note = v)),
          Field(
            label: 'دسته (اختیاری)',
            child: SelectBox(
              text: categoryId != null ? (cat?.name ?? 'دسته') : 'بدون دسته',
              placeholder: categoryId == null,
              onTap: () async {
                final r = await showCategoryPicker(ctx, title: 'دسته هزینه', kind: 'expense', categories: s.categories, value: categoryId, allowNone: true, noneLabel: 'بدون دسته');
                if (r != null) setSt(() => categoryId = r == kNone ? null : r);
              },
            ),
          ),
          AppButton(editing != null ? 'ذخیره' : 'افزودن به برنامه', expand: true, onPressed: !canSubmit || submitting
              ? null
              : () {
                  Navigator.pop(ctx);
                  final a = _toPositive(amount)!;
                  final nt = note.trim().isEmpty ? null : note.trim();
                  if (editing != null) {
                    _update(editing.id, title.trim(), a, nt, categoryId);
                  } else {
                    _insert(s, title: title.trim(), amount: a, categoryId: categoryId, note: nt, sourceType: 'manual');
                  }
                }),
        ]);
      });
    });
  }

  Future<void> _update(String id, String title, double amount, String? note, String? categoryId) async {
    final snapshot = items;
    setState(() {
      submitting = true;
      pending.add(id);
      items = [
        for (final i in items)
          i.id == id
              ? ExpensePlanItem(id: i.id, userId: i.userId, monthStartString: i.monthStartString, title: title, amountToman: amount, categoryId: categoryId, note: note, sourceType: i.sourceType, sourceId: i.sourceId, sortOrder: i.sortOrder)
              : i,
      ];
    });
    try {
      final data = await _c.from('expense_plan_items').update({'title': title, 'amount_toman': amount, 'note': note, 'category_id': categoryId}).eq('id', id).select().single();
      final saved = ExpensePlanItem.fromJson(data);
      setState(() => items = [for (final i in items) i.id == id ? saved : i]);
    } catch (_) {
      setState(() => items = snapshot);
      Toast.error('ویرایش آیتم ناموفق بود.');
    } finally {
      if (mounted) {
        setState(() {
          pending.remove(id);
          submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<PortfolioStore>();
    final suggestions = buildPlanSuggestions(
        period: target, items: items, installments: installments, loans: loans, checks: checks, recurring: recurring, subscriptions: subscriptions, currencyRates: s.currencyRates, assets: s.assets);
    final total = items.fold<double>(0, (a, i) => a + i.amountToman);
    final today = todayStr();
    final actual = monthKey.compareTo(today) <= 0 ? rollupCategories(transactions: s.transactions, categories: s.categories, period: target, kind: 'expense', currencyMode: 'TOMAN').total : null;
    final capsTotal = sumCategoryCapsToman(caps, s.categories, 'expense');
    String display(double t) => s.currencyMode == 'USD' && s.usdRate > 0 ? formatCurrency(t / s.usdRate, 'USD') : formatCurrency(t, 'TOMAN');
    final tj = todayJalaali();
    final isCurrentMonth = target.start.jy == tj.jy && target.start.jm == tj.jm;
    final expenseCats = {for (final c in s.categories.where((c) => c.kind == 'expense')) c.id: c};

    Widget badge(String text) => Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: C.purple500.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
          child: Text(text, style: const TextStyle(fontSize: 10, color: C.purple300)),
        );

    return SubPage(
      title: 'برنامه هزینه',
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
          const Text('پیش‌بینی هزینه‌های ماهانه', style: TextStyle(fontSize: 12, color: C.slate500)),
          const SizedBox(height: 10),
          AppCard(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              IconBtn(Icons.chevron_right, onTap: () => _shift(-1)),
              Expanded(
                child: Column(children: [
                  Text(formatPeriodLabel(target), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                  Text(isCurrentMonth ? 'ماه جاری' : 'ماه هدف', style: const TextStyle(fontSize: 11, color: C.slate500)),
                ]),
              ),
              IconBtn(Icons.chevron_left, onTap: () => _shift(1)),
            ]),
          ),
          const SizedBox(height: 12),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('جمع برآورد هزینه', style: TextStyle(fontSize: 12, color: C.slate400)),
              Money(display(total), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
              Text('${items.length} آیتم${suggestions.isNotEmpty ? ' · ${suggestions.length} پیشنهاد' : ''}', style: const TextStyle(fontSize: 11, color: C.slate500)),
              if (capsTotal > 0) ...[
                const Divider(color: C.white10, height: 20),
                const Text('جمع سقف دسته‌های هزینه', style: TextStyle(fontSize: 12, color: C.slate400)),
                Money(display(capsTotal), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: C.slate200)),
                const Text('برآورد بر اساس سقف‌های تنظیم‌شده در دسته‌بندی‌ها', style: TextStyle(fontSize: 11, color: C.slate500)),
              ],
              if (actual != null) ...[
                const Divider(color: C.white10, height: 20),
                Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('هزینه واقعی', style: TextStyle(fontSize: 11, color: C.slate400)),
                      Money(display(actual), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: C.slate200)),
                    ]),
                  ),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('اختلاف (برنامه − واقعی)', style: TextStyle(fontSize: 11, color: C.slate400)),
                      Money(display(total - actual), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: total - actual >= 0 ? C.emerald400 : C.rose400)),
                    ]),
                  ),
                ]),
              ],
            ]),
          ),
          const SizedBox(height: 16),
          if (loading)
            const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
          else ...[
            Row(children: [
              const Expanded(child: Text('آیتم‌های برنامه', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white))),
              TextButton.icon(onPressed: () => _openManual(s), icon: const Icon(Icons.add, size: 14), label: const Text('افزودن')),
            ]),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('هنوز آیتمی اضافه نشده. دستی اضافه کنید یا از پیشنهادها انتخاب کنید.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: C.slate500)),
              )
            else
              for (final it in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Opacity(
                    opacity: pending.contains(it.id) ? 0.6 : 1,
                    child: AppCard(
                      padding: const EdgeInsets.all(12),
                      onTap: it.sourceType == 'manual' ? () => _openManual(s, it) : null,
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Flexible(child: Text(it.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.slate200))),
                              if (it.sourceType != 'manual') badge(_sourceLabels[it.sourceType] ?? it.sourceType),
                            ]),
                            if ((it.note ?? '').isNotEmpty) Text(it.note!, style: const TextStyle(fontSize: 11, color: C.slate500)),
                            if (it.categoryId != null && expenseCats[it.categoryId] != null) Text(expenseCats[it.categoryId]!.name, style: const TextStyle(fontSize: 10, color: C.slate500)),
                          ]),
                        ),
                        Money(display(it.amountToman), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: C.slate200)),
                        IconButton(onPressed: submitting ? null : () => _delete(it.id), icon: const Icon(Icons.delete_outline, size: 16, color: C.rose300)),
                      ]),
                    ),
                  ),
                ),
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Row(children: [
                Icon(Icons.auto_awesome, size: 16, color: C.amber300),
                SizedBox(width: 6),
                Text('پیشنهادها', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
              ]),
              const Text('اقساط باقی‌مانده، چک‌های در انتظار و هزینه‌های دوره‌ای این ماه', style: TextStyle(fontSize: 11, color: C.slate500)),
              const SizedBox(height: 8),
              for (final sg in suggestions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    padding: const EdgeInsets.all(12),
                    borderColor: C.amber.withValues(alpha: 0.2),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [Flexible(child: Text(sg.title, style: const TextStyle(fontSize: 13, color: C.slate200))), badge(_sourceLabels[sg.sourceType]!)]),
                          if (sg.subtitle != null) Text(sg.subtitle!, style: const TextStyle(fontSize: 11, color: C.slate500)),
                        ]),
                      ),
                      Money(display(sg.amountToman), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: C.slate300)),
                      const SizedBox(width: 6),
                      AppButton('افزودن', dense: true, onPressed: submitting
                          ? null
                          : () => _insert(s, title: sg.title, amount: sg.amountToman, categoryId: sg.categoryId, note: sg.note, sourceType: sg.sourceType, sourceId: sg.sourceId)),
                    ]),
                  ),
                ),
            ],
          ],
        ]),
      ),
    );
  }
}
