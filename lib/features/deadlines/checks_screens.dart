// Ports of ChecksHubView.tsx and CheckFormView.tsx.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/router.dart';
import '../../core/logic/domain_utils.dart';
import '../../core/logic/ledger.dart';
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
import '../transactions/tx_logic.dart';

const _statusLabel = {'pending': 'در انتظار', 'cleared': 'وصول شده', 'bounced': 'برگشتی', 'cancelled': 'لغو شده'};

class ChecksHubScreen extends StatefulWidget {
  const ChecksHubScreen({super.key});
  @override
  State<ChecksHubScreen> createState() => _ChecksHubScreenState();
}

class _ChecksHubScreenState extends State<ChecksHubScreen> {
  List<Check> checks = [];
  String filter = 'pending';
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
      final data = await _c.from('checks').select().isFilter('deleted_at', null).order('due_date_string', ascending: true).order('created_at', ascending: false);
      checks = (data as List).cast<Json>().map(Check.fromJson).toList();
    } catch (_) {
      Toast.error('خطا در دریافت چک‌ها.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _status(Check ch, String status, String ok, String fail) async {
    setState(() => submitting = true);
    try {
      await _c.from('checks').update({'status': status, 'updated_at': DateTime.now().toUtc().toIso8601String()}).eq('id', ch.id).eq('status', 'pending');
      Toast.success(ok);
      await _refresh();
    } catch (_) {
      Toast.error(fail);
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<void> _delete(Check ch) async {
    setState(() => submitting = true);
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      await _c.from('checks').update({'deleted_at': now, 'updated_at': now}).eq('id', ch.id);
      Toast.success('چک حذف شد.');
      await _refresh();
    } catch (_) {
      Toast.error('خطا در حذف چک.');
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<void> _settle(PortfolioStore s, Check ch, String walletId) async {
    final user = s.user;
    final w = findWallet(s.wallets, walletId);
    if (user == null) {
      Toast.error('کیف پول پرداخت را انتخاب کن.');
      return;
    }
    if (w == null) {
      Toast.error('اطلاعات پرداخت نامعتبر است.');
      return;
    }
    final checkRate = tomanPerUnit(ch.currency, s.currencyRates);
    final payRate = tomanPerUnit(w.currency, s.currencyRates);
    if (checkRate <= 0 || payRate <= 0 || s.usdRate <= 0) {
      Toast.error('نرخ تبدیل برای تسویه در دسترس نیست.');
      return;
    }
    final pay = ch.amount * checkRate / payRate;
    final snapUsd = usdRateOn(s.rateHistories, ch.dueDateString, todayStr(), s.usdRate);
    if (!pay.isFinite || pay <= 0) {
      Toast.error('مبلغ تسویه نامعتبر است.');
      return;
    }
    final note = [ch.title, if ((ch.bankName ?? '').isNotEmpty) ch.bankName!, if ((ch.checkNumber ?? '').isNotEmpty) '#${ch.checkNumber}'].join(' · ');
    setState(() => submitting = true);
    try {
      final txData = await _c
          .from('transactions')
          .insert({
            'user_id': user.id,
            'type': 'EXPENSE',
            'date_string': ch.dueDateString,
            'note': note,
            'source_wallet_id': w.id,
            'source_asset_id': null,
            'target_wallet_id': null,
            'target_asset_id': null,
            'source_amount': pay,
            'target_amount': null,
            'category_id': ch.categoryId,
            'asset_id': null,
            'amount': null,
            'price_toman': w.currency == 'IRT' ? null : payRate,
            'usd_rate': w.currency == 'IRT' ? null : snapUsd,
            'amount_toman_at_time': pay * payRate,
            'amount_usd_at_time': pay * payRate / snapUsd,
          })
          .select()
          .single();
      final created = Transaction.fromJson(txData);
      List rows;
      try {
        final now = DateTime.now().toUtc().toIso8601String();
        rows = await _c
            .from('checks')
            .update({'status': 'cleared', 'cleared_at': now, 'paid_transaction_id': created.id, 'updated_at': now})
            .eq('id', ch.id)
            .eq('status', 'pending')
            .select('id');
      } catch (e) {
        await _c.from('transactions').delete().eq('id', created.id);
        rethrow;
      }
      if (rows.isEmpty) {
        await _c.from('transactions').delete().eq('id', created.id);
        Toast.error('این چک قبلاً تسویه شده.');
        await _refresh();
        return;
      }
      s.update((st) => st.transactions = [created, ...st.transactions]);
      Api.fireExpenseAlert([created.id]);
      Toast.success('چک تسویه شد و تراکنش ثبت شد.');
      await _refresh();
    } catch (_) {
      Toast.error('خطا در تسویه چک.');
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<void> _openSettle(PortfolioStore s, Check ch) async {
    String? walletId = ch.walletId ?? (s.wallets.isNotEmpty ? s.wallets.first.id : null);
    await showAppSheet(context, title: 'تسویه چک', builder: (ctx) {
      return StatefulBuilder(builder: (ctx, setSt) {
        final w = findWallet(s.wallets, walletId);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(ch.title, style: const TextStyle(fontSize: 13, color: C.slate300)),
          const SizedBox(height: 12),
          SelectBox(
            text: w?.name ?? 'انتخاب کیف پول',
            placeholder: w == null,
            leading: const Icon(Icons.account_balance_wallet_outlined, size: 16, color: C.slate400),
            onTap: () async {
              final r = await showListPicker(ctx, title: 'انتخاب کیف پول پرداخت', items: [for (final x in s.wallets) PickItem(id: x.id, label: '${x.name} · ${x.currency}')], value: walletId);
              if (r != null && r != kNone) setSt(() => walletId = r);
            },
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: AppButton(w != null ? 'ثبت تسویه با ${w.name}' : 'ثبت تسویه', expand: true, onPressed: walletId == null
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      _settle(s, ch, walletId!);
                    }),
            ),
            const SizedBox(width: 8),
            AppButton('انصراف', variant: BtnVariant.secondary, onPressed: () => Navigator.pop(ctx)),
          ]),
        ]);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<PortfolioStore>();
    final filtered = filter == 'all'
        ? checks
        : filter == 'cleared'
            ? checks.where((c) => c.status == 'cleared' || c.status == 'bounced' || c.status == 'cancelled').toList()
            : checks.where((c) => c.status == 'pending').toList();
    final todayS = todayStr();
    double display(Check c) {
      final r = tomanPerUnit(c.currency, s.currencyRates);
      final t = r > 0 ? c.amount * r : 0.0;
      if (!(t > 0)) return c.amount;
      return s.currencyMode == 'USD' && s.usdRate > 0 ? t / s.usdRate : t;
    }

    return SubPage(
      title: 'چک‌ها',
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Nav.push(context, '/deadlines/checks/new');
            _refresh();
          },
          icon: const Icon(Icons.add, size: 16),
          label: const Text('چک جدید'),
        ),
      ],
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
          Segmented<String>(options: const [('pending', 'در انتظار'), ('cleared', 'بسته شده'), ('all', 'همه')], value: filter, onChanged: (v) => setState(() => filter = v)),
          const SizedBox(height: 14),
          if (loading)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('در حال دریافت...', style: TextStyle(color: C.slate500))))
          else if (filtered.isEmpty)
            EmptyState(
              icon: Icons.receipt_long_outlined,
              title: filter == 'pending' ? 'چک در انتظاری ندارید.' : 'موردی برای نمایش نیست.',
              description: filter == 'pending' ? 'چک‌های صادره را با تاریخ سررسید ثبت کنید تا سررسید را از دست ندهید.' : null,
              actionLabel: filter == 'pending' ? 'ثبت اولین چک' : null,
              onAction: filter == 'pending'
                  ? () async {
                      await Nav.push(context, '/deadlines/checks/new');
                      _refresh();
                    }
                  : null,
            )
          else
            for (final ch in filtered)
              Builder(builder: (_) {
                final cat = ch.categoryId == null ? null : s.categories.where((c) => c.id == ch.categoryId).firstOrNull;
                final due = parseJalaali(ch.dueDateString);
                final days = daysBetweenJalaali(todayS, ch.dueDateString);
                final overdue = ch.status == 'pending' && days != null && days < 0;
                final isToday = ch.status == 'pending' && days == 0;
                final (bg, fg) = ch.status == 'pending'
                    ? (overdue ? (C.rose, C.rose300) : (isToday ? (C.amber, C.amber300) : (C.sky400, const Color(0xFF7DD3FC))))
                    : ch.status == 'cleared'
                        ? (C.emerald, C.emerald300)
                        : ch.status == 'bounced'
                            ? (C.rose, C.rose300)
                            : (C.slate500, C.slate400);
                final sub = [ch.bankName, if ((ch.checkNumber ?? '').isNotEmpty) '#${ch.checkNumber}', cat?.name].whereType<String>().where((x) => x.isNotEmpty).join(' · ');
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(ch.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                            Text(sub.isEmpty ? '—' : sub, style: const TextStyle(fontSize: 11, color: C.slate500)),
                          ]),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: bg.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                          child: Text(_statusLabel[ch.status] ?? ch.status, style: TextStyle(fontSize: 11, color: fg)),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(child: StatPill(label: 'مبلغ', value: formatCurrency(display(ch), s.currencyMode))),
                        const SizedBox(width: 8),
                        Expanded(child: StatPill(label: 'سررسید', value: due != null ? toPersianDigits(formatJalaaliHuman(due)) : ch.dueDateString)),
                      ]),
                      if (ch.status == 'pending') ...[
                        const SizedBox(height: 10),
                        Wrap(spacing: 6, runSpacing: 6, children: [
                          AppButton('تسویه', icon: Icons.credit_card, dense: true, onPressed: submitting ? null : () => _openSettle(s, ch)),
                          AppButton('برگشت', icon: Icons.cancel_outlined, dense: true, variant: BtnVariant.danger,
                              onPressed: submitting ? null : () => _status(ch, 'bounced', 'چک به‌عنوان برگشتی ثبت شد.', 'خطا در ثبت برگشت چک.')),
                          AppButton('عودت', icon: Icons.block, dense: true, variant: BtnVariant.secondary,
                              onPressed: submitting ? null : () => _status(ch, 'cancelled', 'چک عودت/لغو شد.', 'خطا در عودت چک.')),
                          AppButton('ویرایش', dense: true, variant: BtnVariant.secondary, onPressed: () async {
                            await Nav.push(context, '/deadlines/checks/${ch.id}/edit');
                            _refresh();
                          }),
                          AppButton('حذف', icon: Icons.delete_outline, dense: true, variant: BtnVariant.ghost, onPressed: submitting ? null : () => _delete(ch)),
                        ]),
                      ],
                    ]),
                  ),
                );
              }),
        ]),
      ),
    );
  }
}

class CheckFormScreen extends StatefulWidget {
  final String? checkId;
  const CheckFormScreen({super.key, this.checkId});
  @override
  State<CheckFormScreen> createState() => _CheckFormScreenState();
}

class _CheckFormScreenState extends State<CheckFormScreen> {
  String title = '', bankName = '', checkNumber = '', amount = '', note = '';
  String? walletId, categoryId;
  late String dueDate = todayStr();
  late bool loading = widget.checkId != null;
  bool submitting = false;
  int formKey = 0;
  bool get isEdit => widget.checkId != null;

  @override
  void initState() {
    super.initState();
    if (isEdit) _load();
  }

  Future<void> _load() async {
    try {
      final data = await Supabase.instance.client.from('checks').select().eq('id', widget.checkId!).isFilter('deleted_at', null).single();
      final ch = Check.fromJson(data);
      if (ch.status != 'pending') {
        Toast.error('فقط چک‌های در انتظار قابل ویرایش هستند.');
        if (mounted) Navigator.pop(context);
        return;
      }
      setState(() {
        title = ch.title;
        bankName = ch.bankName ?? '';
        checkNumber = ch.checkNumber ?? '';
        amount = jsNumStr(ch.amount);
        walletId = ch.walletId;
        categoryId = ch.categoryId;
        dueDate = ch.dueDateString;
        note = ch.note ?? '';
        formKey++;
      });
    } catch (_) {
      Toast.error('خطا در دریافت اطلاعات چک.');
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _submit(PortfolioStore s) async {
    final user = s.user;
    if (user == null) {
      Toast.error('کاربر معتبر نیست.');
      return;
    }
    String? err;
    if (title.trim().isEmpty) {
      err = 'عنوان الزامی است.';
    } else if (parseJalaali(dueDate) == null) {
      err = 'تاریخ سررسید نامعتبر است.';
    } else if (walletId == null) {
      err = 'کیف پول پیش‌فرض تسویه الزامی است.';
    } else if (categoryId == null) {
      err = 'انتخاب دسته هزینه الزامی است.';
    } else if (!(n(amount).isFinite && n(amount) > 0)) {
      err = 'مبلغ چک نامعتبر است.';
    }
    if (err != null) {
      Toast.error(err);
      return;
    }
    final w = findWallet(s.wallets, walletId)!;
    setState(() => submitting = true);
    try {
      final payload = {
        'title': title.trim(),
        'bank_name': bankName.trim().isEmpty ? null : bankName.trim(),
        'check_number': checkNumber.trim().isEmpty ? null : checkNumber.trim(),
        'amount': n(amount),
        'currency': w.currency,
        'due_date_string': dueDate,
        'wallet_id': walletId,
        'category_id': categoryId,
        'note': note.trim().isEmpty ? null : note.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      final c = Supabase.instance.client;
      if (isEdit) {
        await c.from('checks').update(payload).eq('id', widget.checkId!);
        Toast.success('چک ویرایش شد.');
      } else {
        await c.from('checks').insert({...payload, 'user_id': user.id, 'status': 'pending', 'deleted_at': null});
        Toast.success('چک ثبت شد.');
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      Toast.error(isEdit ? 'خطا در ویرایش چک.' : 'خطا در ثبت چک.');
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<PortfolioStore>();
    if (loading) return SubPage(title: isEdit ? 'ویرایش چک' : 'ثبت چک جدید', body: const Center(child: Text('در حال دریافت...', style: TextStyle(color: C.slate500))));
    final w = findWallet(s.wallets, walletId);
    final cat = s.categories.where((c) => c.id == categoryId && c.kind == 'expense').firstOrNull;
    return SubPage(
      title: isEdit ? 'ویرایش چک' : 'ثبت چک جدید',
      body: ListView(key: ValueKey(formKey), padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
        Field(label: 'عنوان / دریافت‌کننده', child: AppTextField(value: title, onChanged: (v) => title = v, hint: 'مثال: اجاره دفتر')),
        Field(label: 'نام بانک', child: AppTextField(value: bankName, onChanged: (v) => bankName = v, hint: 'اختیاری')),
        Field(label: 'شماره چک', child: AppTextField(value: checkNumber, onChanged: (v) => checkNumber = v, hint: 'اختیاری', ltr: true)),
        Field(label: 'مبلغ چک', child: NumberInput(value: amount, onChanged: (v) => amount = v)),
        Field(
          label: 'کیف پول (ارز و تسویه پیش‌فرض)',
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
        Field(label: 'تاریخ سررسید', child: DateField(value: dueDate, onChanged: (v) => setState(() => dueDate = v))),
        Field(label: 'یادداشت', child: AppTextField(value: note, onChanged: (v) => note = v, maxLines: 3, hint: 'اختیاری')),
        AppButton(submitting ? 'در حال ذخیره...' : (isEdit ? 'ذخیره تغییرات' : 'ثبت چک'), expand: true, onPressed: submitting ? null : () => _submit(s)),
      ]),
    );
  }
}
