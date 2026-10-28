// Ports of SubscriptionsHubView.tsx and SubscriptionFormView.tsx.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/router.dart';
import '../../core/logic/domain_utils.dart';
import '../../core/models.dart';
import '../../core/services/api.dart';
import '../../core/store.dart';
import '../../core/ui/category_picker.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/toast.dart';
import '../../core/ui/widgets.dart';
import '../../core/utils/digits.dart';
import '../../core/utils/format.dart';
import '../../core/utils/jalali.dart';
import '../../core/utils/period.dart';
import '../dashboard/home_tab.dart' show SubscriptionAmountText;
import '../transactions/tx_logic.dart';
import 'loans_screens.dart' show ReminderDaysField;

const _statusLabel = {'active': 'فعال', 'cancelled': 'لغو شده'};

class SubscriptionsHubScreen extends StatefulWidget {
  const SubscriptionsHubScreen({super.key});
  @override
  State<SubscriptionsHubScreen> createState() => _SubscriptionsHubScreenState();
}

class _SubscriptionsHubScreenState extends State<SubscriptionsHubScreen> {
  List<Subscription> rows = [];
  String filter = 'active';
  Period summaryPeriod = currentPeriod('month');
  bool loading = true, submitting = false;
  SupabaseClient get _c => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => loading = true);
    try {
      final data = await _c.from('subscriptions').select().isFilter('deleted_at', null).order('next_due_date_string', ascending: true).order('created_at', ascending: false);
      rows = (data as List).cast<Json>().map(Subscription.fromJson).toList();
    } catch (_) {
      Toast.error('خطا در دریافت اشتراک‌ها.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _run(Future<void> Function() fn, String ok, String fail) async {
    setState(() => submitting = true);
    try {
      await fn();
      Toast.success(ok);
      await _refresh();
    } catch (_) {
      Toast.error(fail);
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  String get _now => DateTime.now().toUtc().toIso8601String();

  Future<void> _cancel(Subscription r) => _run(
        () => _c.from('subscriptions').update({'status': 'cancelled', 'cancelled_at': _now, 'updated_at': _now}).eq('id', r.id).eq('status', 'active'),
        'اشتراک لغو شد.',
        'خطا در لغو اشتراک.',
      );

  Future<void> _reactivate(Subscription r) => _run(
        () => _c.from('subscriptions').update({'status': 'active', 'cancelled_at': null, 'updated_at': _now}).eq('id', r.id).eq('status', 'cancelled'),
        'اشتراک دوباره فعال شد.',
        'خطا در فعال‌سازی اشتراک.',
      );

  Future<void> _delete(Subscription r) => _run(
        () => _c.from('subscriptions').update({'deleted_at': _now, 'updated_at': _now}).eq('id', r.id),
        'اشتراک حذف شد.',
        'خطا در حذف اشتراک.',
      );

  Future<void> _settle(PortfolioStore s, Subscription r, String walletId) async {
    setState(() => submitting = true);
    try {
      final (status, body) = await Api.post('/api/subscriptions/settle', {'subscriptionId': r.id, 'walletId': walletId});
      if (status < 200 || status >= 300 || body['ok'] != true) {
        final e = body['error'];
        Toast.error(e is String && e.isNotEmpty ? e : 'خطا در تسویه اشتراک.');
        return;
      }
      final txData = await _c.from('transactions').select().eq('id', body['transactionId'] as String).maybeSingle();
      if (txData != null) {
        final tx = Transaction.fromJson(txData);
        s.update((st) => st.transactions = [tx, ...st.transactions]);
      }
      Toast.success('اشتراک تسویه شد و تراکنش ثبت شد.');
      await _refresh();
    } catch (_) {
      Toast.error('خطا در تسویه اشتراک.');
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<void> _openSettle(PortfolioStore s, Subscription r) async {
    String? walletId = r.walletId ?? (s.wallets.isNotEmpty ? s.wallets.first.id : null);
    await showAppSheet(context, title: 'پرداخت اشتراک', builder: (ctx) {
      return StatefulBuilder(builder: (ctx, setSt) {
        final w = findWallet(s.wallets, walletId);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(r.platform, style: const TextStyle(fontSize: 13, color: C.slate300)),
          const SizedBox(height: 12),
          SelectBox(
            text: w?.name ?? 'انتخاب کیف پول',
            placeholder: w == null,
            leading: const Icon(Icons.account_balance_wallet_outlined, size: 16, color: C.slate400),
            onTap: () async {
              final x = await showListPicker(ctx, title: 'انتخاب کیف پول پرداخت', items: [for (final x in s.wallets) PickItem(id: x.id, label: '${x.name} · ${x.currency}')], value: walletId);
              if (x != null && x != kNone) setSt(() => walletId = x);
            },
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: AppButton(w != null ? 'ثبت پرداخت با ${w.name}' : 'ثبت پرداخت', expand: true, onPressed: walletId == null
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      _settle(s, r, walletId!);
                    }),
            ),
            const SizedBox(width: 8),
            AppButton('انصراف', variant: BtnVariant.secondary, onPressed: () => Navigator.pop(ctx)),
          ]),
        ]);
      });
    });
  }

  Future<void> _openNew() async {
    await Nav.push(context, '/deadlines/subscriptions/new');
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<PortfolioStore>();
    final filtered = filter == 'all' ? rows : rows.where((r) => r.status == (filter == 'cancelled' ? 'cancelled' : 'active')).toList();
    final todayS = todayStr();

    final lineItems = <(Subscription, int, double)>[];
    for (final r in rows.where((r) => r.status == 'active')) {
      final dues = subscriptionDueDatesInPeriod(r, summaryPeriod);
      if (dues.isEmpty) continue;
      final total = subscriptionAmountToToman(r.amount, r.currency, s.currencyRates) * dues.length;
      lineItems.add((r, dues.length, s.currencyMode == 'USD' && s.usdRate > 0 ? total / s.usdRate : total));
    }
    final total = lineItems.fold<double>(0, (a, e) => a + e.$3);

    return SubPage(
      title: 'اشتراک‌ها',
      actions: [TextButton.icon(onPressed: _openNew, icon: const Icon(Icons.add, size: 16), label: const Text('اشتراک جدید'))],
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('هزینه ماهانه', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                    Text('جمع اشتراک‌های فعال در ماه انتخاب‌شده', style: TextStyle(fontSize: 11, color: C.slate500)),
                  ]),
                ),
                IconBtn(Icons.chevron_right, onTap: () => setState(() => summaryPeriod = shiftPeriod(summaryPeriod, -1))),
                Text(formatPeriodLabel(summaryPeriod), style: const TextStyle(fontSize: 12, color: C.slate300)),
                IconBtn(Icons.chevron_left, onTap: () => setState(() => summaryPeriod = shiftPeriod(summaryPeriod, 1))),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                const Text('جمع', style: TextStyle(fontSize: 12, color: C.slate400)),
                const Spacer(),
                Money(formatCurrency(total, s.currencyMode), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
              ]),
              const SizedBox(height: 8),
              if (lineItems.isEmpty)
                const Text('سررسیدی در این ماه نیست.', style: TextStyle(fontSize: 12, color: C.slate500))
              else
                for (final (r, count, display) in lineItems)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(r.platform, style: const TextStyle(fontSize: 12, color: C.slate200)),
                          Text('${toPersianDigits(count)} بار', style: const TextStyle(fontSize: 10, color: C.slate500)),
                        ]),
                      ),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Money(formatCurrency(display, s.currencyMode), style: const TextStyle(fontSize: 12, color: C.slate200)),
                        if (r.currency != 'IRT') Money(formatSubscriptionNativeAmount(r.amount * count, r.currency), style: const TextStyle(fontSize: 10, color: C.slate500)),
                      ]),
                    ]),
                  ),
            ]),
          ),
          const SizedBox(height: 14),
          Segmented<String>(options: const [('active', 'فعال'), ('cancelled', 'لغو شده'), ('all', 'همه')], value: filter, onChanged: (v) => setState(() => filter = v)),
          const SizedBox(height: 14),
          if (loading)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('در حال دریافت...', style: TextStyle(color: C.slate500))))
          else if (filtered.isEmpty)
            EmptyState(
              icon: Icons.repeat,
              title: filter == 'active' ? 'اشتراک فعالی ندارید.' : 'موردی برای نمایش نیست.',
              description: filter == 'active' ? 'اشتراک‌های دوره‌ای را ثبت کنید تا سررسید را از دست ندهید.' : null,
              actionLabel: filter == 'active' ? 'ثبت اولین اشتراک' : null,
              onAction: filter == 'active' ? _openNew : null,
            )
          else
            for (final r in filtered) _row(s, r, todayS),
        ]),
      ),
    );
  }

  Widget _row(PortfolioStore s, Subscription r, String todayS) {
    final cat = r.categoryId == null ? null : s.categories.where((c) => c.id == r.categoryId).firstOrNull;
    final w = r.walletId == null ? null : findWallet(s.wallets, r.walletId);
    final due = parseJalaali(r.nextDueDateString);
    final days = daysBetweenJalaali(todayS, r.nextDueDateString);
    final active = r.status == 'active';
    final overdue = active && days != null && days < 0;
    final isToday = active && days == 0;
    final (bg, fg) = active ? (overdue ? (C.rose, C.rose300) : (isToday ? (C.amber, C.amber300) : (C.emerald, C.emerald300))) : (C.slate500, C.slate400);
    final sub = [intervalLabel(r.intervalNumber, r.intervalPeriod), cat?.name, w?.name].whereType<String>().where((x) => x.isNotEmpty).join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.platform, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                Text(sub.isEmpty ? '—' : sub, style: const TextStyle(fontSize: 11, color: C.slate500)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: bg.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
              child: Text(_statusLabel[r.status] ?? r.status, style: TextStyle(fontSize: 11, color: fg)),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(12)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('مبلغ', style: TextStyle(fontSize: 10, color: C.slate500)),
                  const SizedBox(height: 2),
                  SubscriptionAmountText(amount: r.amount, currency: r.currency, store: s),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: StatPill(label: 'سررسید بعدی', value: due != null ? toPersianDigits(formatJalaaliHuman(due)) : r.nextDueDateString)),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            if (active) ...[
              AppButton('پرداخت', icon: Icons.credit_card, dense: true, onPressed: submitting ? null : () => _openSettle(s, r)),
              AppButton('لغو', icon: Icons.cancel_outlined, dense: true, variant: BtnVariant.secondary, onPressed: submitting ? null : () => _cancel(r)),
            ] else
              AppButton('فعال‌سازی', icon: Icons.restart_alt, dense: true, variant: BtnVariant.secondary, onPressed: submitting ? null : () => _reactivate(r)),
            AppButton('ویرایش', dense: true, variant: BtnVariant.secondary, onPressed: () async {
              await Nav.push(context, '/deadlines/subscriptions/${r.id}/edit');
              _refresh();
            }),
            AppButton('حذف', icon: Icons.delete_outline, dense: true, variant: BtnVariant.ghost, onPressed: submitting ? null : () => _delete(r)),
          ]),
        ]),
      ),
    );
  }
}

class SubscriptionFormScreen extends StatefulWidget {
  final String? subscriptionId;
  const SubscriptionFormScreen({super.key, this.subscriptionId});
  @override
  State<SubscriptionFormScreen> createState() => _SubscriptionFormScreenState();
}

class _SubscriptionFormScreenState extends State<SubscriptionFormScreen> {
  String platform = '', amount = '', note = '', intervalNumber = '1', intervalPeriod = 'month';
  String? walletId, categoryId;
  late String nextDueDate = todayStr();
  List<int> reminderDays = [];
  late bool loading = widget.subscriptionId != null;
  bool submitting = false;
  int formKey = 0;
  bool get isEdit => widget.subscriptionId != null;

  @override
  void initState() {
    super.initState();
    if (isEdit) _load();
  }

  Future<void> _load() async {
    try {
      final data = await Supabase.instance.client.from('subscriptions').select().eq('id', widget.subscriptionId!).isFilter('deleted_at', null).single();
      final r = Subscription.fromJson(data);
      setState(() {
        platform = r.platform;
        amount = jsNumStr(r.amount);
        walletId = r.walletId;
        categoryId = r.categoryId;
        nextDueDate = r.nextDueDateString;
        intervalNumber = '${r.intervalNumber}';
        intervalPeriod = r.intervalPeriod;
        reminderDays = r.reminderDaysBefore;
        note = r.note ?? '';
        formKey++;
      });
    } catch (_) {
      Toast.error('خطا در دریافت اطلاعات اشتراک.');
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String? _validate() {
    if (platform.trim().isEmpty) return 'نام پلتفرم الزامی است.';
    if (parseJalaali(nextDueDate) == null) return 'تاریخ سررسید نامعتبر است.';
    if (walletId == null) return 'کیف پول پیش‌فرض الزامی است.';
    if (categoryId == null) return 'انتخاب دسته هزینه الزامی است.';
    final a = n(amount);
    if (!a.isFinite || a <= 0) return 'مبلغ نامعتبر است.';
    final i = n(intervalNumber);
    if (!i.isFinite || i != i.truncateToDouble() || i <= 0) return 'فاصله تکرار نامعتبر است.';
    return null;
  }

  Future<void> _submit(PortfolioStore s) async {
    final user = s.user;
    if (user == null) {
      Toast.error('کاربر معتبر نیست.');
      return;
    }
    final err = _validate();
    if (err != null) {
      Toast.error(err);
      return;
    }
    final w = findWallet(s.wallets, walletId)!;
    setState(() => submitting = true);
    try {
      final payload = {
        'platform': platform.trim(),
        'amount': n(amount),
        'currency': w.currency,
        'interval_number': n(intervalNumber).toInt(),
        'interval_period': intervalPeriod,
        'next_due_date_string': nextDueDate,
        'wallet_id': walletId,
        'category_id': categoryId,
        'reminder_days_before': normalizeReminderDaysBefore(reminderDays),
        'note': note.trim().isEmpty ? null : note.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      final c = Supabase.instance.client;
      if (isEdit) {
        await c.from('subscriptions').update(payload).eq('id', widget.subscriptionId!);
        Toast.success('اشتراک ویرایش شد.');
      } else {
        await c.from('subscriptions').insert({...payload, 'user_id': user.id, 'status': 'active', 'cancelled_at': null, 'deleted_at': null});
        Toast.success('اشتراک ثبت شد.');
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      Toast.error(isEdit ? 'خطا در ویرایش اشتراک.' : 'خطا در ثبت اشتراک.');
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<PortfolioStore>();
    final title = isEdit ? 'ویرایش اشتراک' : 'ثبت اشتراک جدید';
    if (loading) return SubPage(title: title, body: const Center(child: Text('در حال دریافت...', style: TextStyle(color: C.slate500))));
    final w = findWallet(s.wallets, walletId);
    final cat = s.categories.where((c) => c.id == categoryId && c.kind == 'expense').firstOrNull;
    final inum = n(intervalNumber);
    final preview = inum > 0 ? intervalLabel(inum.toInt(), intervalPeriod) : null;
    return SubPage(
      title: title,
      body: ListView(key: ValueKey(formKey), padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
        Field(label: 'پلتفرم / سرویس', child: AppTextField(value: platform, onChanged: (v) => platform = v, hint: 'مثال: Netflix')),
        Field(
          label: 'کیف پول پیش‌فرض',
          child: SelectBox(
            text: w != null ? '${w.name} · ${w.currency}' : 'انتخاب کنید',
            placeholder: w == null,
            trailing: Icons.chevron_left,
            onTap: () async {
              final r = await showListPicker(context, title: 'انتخاب کیف پول', items: [for (final x in s.wallets) PickItem(id: x.id, label: '${x.name} · ${x.currency}')], value: walletId);
              if (r != null && r != kNone) setState(() => walletId = r);
            },
          ),
        ),
        Field(label: 'مبلغ', hint: w != null ? 'ارز: ${w.currency}' : null, child: NumberInput(value: amount, onChanged: (v) => amount = v)),
        Field(
          label: 'دسته هزینه',
          child: SelectBox(
            text: cat?.name ?? 'انتخاب کنید',
            placeholder: cat == null,
            trailing: Icons.chevron_left,
            onTap: () async {
              final r = await showCategoryPicker(context, title: 'انتخاب دسته هزینه', kind: 'expense', categories: s.categories, value: categoryId);
              if (r != null && r != kNone) setState(() => categoryId = r);
            },
          ),
        ),
        Field(label: 'سررسید بعدی', child: DateField(value: nextDueDate, onChanged: (v) => setState(() => nextDueDate = v))),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Field(label: 'فاصله تکرار', child: NumberInput(value: intervalNumber, onChanged: (v) => setState(() => intervalNumber = v)))),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: Field(
              label: 'واحد',
              child: Segmented<String>(options: [for (final e in kIntervalLabels.entries) (e.key, e.value)], value: intervalPeriod, onChanged: (v) => setState(() => intervalPeriod = v)),
            ),
          ),
        ]),
        if (preview != null)
          Padding(padding: const EdgeInsets.only(bottom: 14), child: Text('تکرار: $preview', style: const TextStyle(fontSize: 12, color: C.purple300))),
        ReminderDaysField(value: reminderDays, onChanged: (v) => setState(() => reminderDays = v)),
        Field(label: 'یادداشت', child: AppTextField(value: note, onChanged: (v) => note = v, maxLines: 2)),
        AppButton(submitting ? 'در حال ذخیره...' : (isEdit ? 'ذخیره تغییرات' : 'ثبت اشتراک'), expand: true, onPressed: submitting ? null : () => _submit(s)),
      ]),
    );
  }
}
