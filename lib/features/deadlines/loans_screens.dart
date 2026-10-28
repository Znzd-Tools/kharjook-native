// Ports of LoansHubView.tsx and LoanFormView.tsx.

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

class _Row {
  final LoanInstallment installment;
  final Loan loan;
  _Row(this.installment, this.loan);
}

const _weekdayShort = ['ش', 'ی', 'د', 'س', 'چ', 'پ', 'ج'];

class LoansHubScreen extends StatefulWidget {
  const LoansHubScreen({super.key});
  @override
  State<LoansHubScreen> createState() => _LoansHubScreenState();
}

class _LoansHubScreenState extends State<LoansHubScreen> {
  String tab = 'loans';
  List<Loan> loans = [];
  List<LoanInstallment> installments = [];
  bool loading = true, submitting = false;
  String loanFilter = 'remaining', installmentFilter = 'remaining';
  late JDate today = todayJalaali();
  late int calY = today.jy, calM = today.jm;
  late String selectedDate = formatJalaali(today);

  SupabaseClient get _c => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => loading = true);
    try {
      final res = await Future.wait([
        _c.from('loans').select().isFilter('deleted_at', null).order('created_at', ascending: false),
        _c.from('loan_installments').select().order('due_date_string', ascending: true).order('sequence_no', ascending: true),
      ]);
      loans = (res[0] as List).cast<Json>().map(Loan.fromJson).toList();
      installments = (res[1] as List).cast<Json>().map(LoanInstallment.fromJson).toList();
    } catch (_) {
      Toast.error('خطا در دریافت اطلاعات اقساط و وام‌ها.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  double _displayAmount(PortfolioStore s, Map<String, Asset> assetsById, _Row r) {
    final principal = r.installment.isPaid ? r.installment.amount : installmentRemainingAmount(r.installment);
    final t = loanAmountToToman(principal, r.loan.currency, r.loan.assetId, s.currencyRates, assetsById);
    if (!(t > 0)) return principal;
    if (s.currencyMode == 'USD' && s.usdRate > 0) return t / s.usdRate;
    return t;
  }

  String _formatLoanQty(PortfolioStore s, Map<String, Asset> assetsById, double amount, Loan loan) {
    if (loan.assetId == null) {
      final t = loanAmountToToman(amount, loan.currency, loan.assetId, s.currencyRates, assetsById);
      return formatCurrency(s.currencyMode == 'USD' && s.usdRate > 0 ? t / s.usdRate : t, s.currencyMode);
    }
    final a = assetsById[loan.assetId];
    return '${formatAssetAmount(amount, a?.decimalPlaces ?? 4)} ${a?.unit ?? ''}'.trim();
  }

  Future<void> _deleteLoan(Loan loan) async {
    setState(() => submitting = true);
    try {
      await _c.from('loans').update({'deleted_at': DateTime.now().toUtc().toIso8601String()}).eq('id', loan.id);
      await _c.from('loan_installments').delete().eq('loan_id', loan.id).eq('is_paid', false);
      Toast.success('وام حذف شد و اقساط باقی‌مانده پاک شدند.');
      await _refresh();
    } catch (_) {
      Toast.error('خطا در حذف وام.');
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<void> _openSettle(PortfolioStore s, LoanInstallment it) async {
    final loan = loans.where((l) => l.id == it.loanId).firstOrNull;
    if (loan == null) return;
    await showAppSheet(context, title: 'تسویه قسط', builder: (_) => _SettleSheet(installment: it, loan: loan, store: s, onDone: _refresh));
  }

  Widget _filterChips(List<(String, String)> opts, String value, ValueChanged<String> onChanged) => Wrap(spacing: 6, children: [
        for (final (v, l) in opts) FilterChipX(active: value == v, label: l, onTap: () => onChanged(v)),
      ]);

  Widget _installmentCard(PortfolioStore s, Map<String, Asset> assetsById, _Row r, Map<String, (int, int)> meta, {bool showDate = true, bool settleOnly = false}) {
    final it = r.installment;
    final m = meta[r.loan.id];
    final total = m?.$1 ?? it.sequenceNo;
    final isLast = it.sequenceNo == (m?.$2 ?? it.sequenceNo);
    final parsed = parseJalaali(it.dueDateString);
    final amountText = r.loan.assetId != null
        ? _formatLoanQty(s, assetsById, it.isPaid ? it.amount : installmentRemainingAmount(it), r.loan)
        : formatCurrency(_displayAmount(s, assetsById, r), s.currencyMode);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(r.loan.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.slate200)),
                Text(toPersianDigits('${it.sequenceNo}/$total'), textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 11, color: C.slate500)),
                if (isLast)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: C.purple500.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                    child: const Text('آخرین قسط', style: TextStyle(fontSize: 9, color: C.purple300)),
                  ),
              ]),
              if (showDate) Text(parsed != null ? formatJalaaliHuman(parsed) : it.dueDateString, style: const TextStyle(fontSize: 11, color: C.slate500)),
              Money(amountText, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
              if (installmentHasPartialPay(it)) const Text('پرداخت جزئی', style: TextStyle(fontSize: 10, color: C.amber300)),
            ]),
          ),
          if (it.isPaid && !settleOnly)
            const Row(children: [Icon(Icons.check_circle_outline, size: 14, color: C.emerald400), SizedBox(width: 4), Text('تسویه‌شده', style: TextStyle(fontSize: 11, color: C.emerald400))])
          else
            AppButton('تسویه', icon: Icons.credit_card, dense: true, onPressed: () => _openSettle(s, it)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<PortfolioStore>();
    final assetsById = {for (final a in s.assets) a.id: a};
    final loansById = {for (final l in loans) l.id: l};
    final meta = <String, (int, int)>{};
    for (final it in installments) {
      final p = meta[it.loanId];
      meta[it.loanId] = p == null ? (1, it.sequenceNo) : (p.$1 + 1, it.sequenceNo > p.$2 ? it.sequenceNo : p.$2);
    }
    final loanRows = loans.map((l) {
      final all = installments.where((i) => i.loanId == l.id).toList();
      return (l, all.where((i) => i.isPaid).length, all.length);
    }).toList();
    final filteredLoans = loanFilter == 'all'
        ? loanRows
        : loanFilter == 'finished'
            ? loanRows.where((r) => r.$3 > 0 && r.$2 >= r.$3).toList()
            : loanRows.where((r) => r.$3 == 0 || r.$2 < r.$3).toList();
    final rows = [for (final it in installments) if (loansById[it.loanId] != null) _Row(it, loansById[it.loanId]!)];
    final filteredRows = installmentFilter == 'all' ? rows : rows.where((r) => installmentFilter == 'paid' ? r.installment.isPaid : !r.installment.isPaid).toList();
    final groups = <String, (String, List<_Row>, double)>{};
    for (final r in filteredRows) {
      final p = parseJalaali(r.installment.dueDateString);
      final key = p != null ? '${p.jy}/${p.jm.toString().padLeft(2, '0')}' : r.installment.dueDateString.substring(0, r.installment.dueDateString.length < 7 ? r.installment.dueDateString.length : 7);
      final label = p != null ? '${kJalaliMonths[p.jm - 1]} ${toPersianDigits(p.jy)}' : key;
      final g = groups[key];
      if (g == null) {
        groups[key] = (label, [r], _displayAmount(s, assetsById, r));
      } else {
        g.$2.add(r);
        groups[key] = (g.$1, g.$2, g.$3 + _displayAmount(s, assetsById, r));
      }
    }
    var remainingToman = 0.0;
    for (final r in rows.where((r) => !r.installment.isPaid)) {
      remainingToman += loanAmountToToman(installmentRemainingAmount(r.installment), r.loan.currency, r.loan.assetId, s.currencyRates, assetsById);
    }
    final remainingDisplay = s.currencyMode == 'USD' ? (s.usdRate > 0 ? remainingToman / s.usdRate : 0.0) : remainingToman;

    // Calendar.
    final monthKey = '$calY/${calM.toString().padLeft(2, '0')}';
    final monthLen = jalaaliMonthLength(calY, calM);
    final firstWd = jalaaliWeekday(JDate(calY, calM, 1));
    final monthRows = rows.where((r) => !r.installment.isPaid && r.installment.dueDateString.startsWith('$monthKey/')).toList();
    final byDate = <String, List<_Row>>{};
    for (final r in monthRows) {
      (byDate[r.installment.dueDateString] ??= []).add(r);
    }
    final sp = parseJalaali(selectedDate);
    if (sp == null || sp.jy != calY || sp.jm != calM) selectedDate = '$monthKey/01';
    final dayRows = byDate[selectedDate] ?? const [];
    final todayS = formatJalaali(today);

    return SubPage(
      title: 'اقساط و وام‌ها',
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Nav.push(context, '/deadlines/loans/new');
            _refresh();
          },
          icon: const Icon(Icons.add, size: 16),
          label: const Text('وام جدید'),
        ),
      ],
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
          Segmented<String>(options: const [('loans', 'وام‌ها'), ('installments', 'اقساط'), ('calendar', 'تقویم بدهی')], value: tab, onChanged: (v) => setState(() => tab = v)),
          const SizedBox(height: 14),
          if (loading)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('در حال دریافت...', style: TextStyle(color: C.slate500))))
          else if (tab == 'loans') ...[
            if (loanRows.isEmpty)
              EmptyState(
                title: 'هنوز وامی ثبت نشده.',
                actionLabel: 'ایجاد اولین وام',
                onAction: () async {
                  await Nav.push(context, '/deadlines/loans/new');
                  _refresh();
                },
              )
            else ...[
              _filterChips(const [('all', 'همه'), ('remaining', 'باقی‌مانده'), ('finished', 'تمام‌شده')], loanFilter, (v) => setState(() => loanFilter = v)),
              const SizedBox(height: 12),
              if (filteredLoans.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('موردی با این فیلتر وجود ندارد.', textAlign: TextAlign.center, style: TextStyle(color: C.slate500, fontSize: 12))),
              for (final (loan, paid, total) in filteredLoans)
                Builder(builder: (_) {
                  final cat = loan.categoryId == null ? null : s.categories.where((c) => c.id == loan.categoryId).firstOrNull;
                  final la = loan.assetId != null ? assetsById[loan.assetId] : null;
                  final totalDisplay = loan.totalAmount ?? loan.installmentAmount * loan.repeatCount;
                  final pct = total > 0 ? (paid / total * 100).round() : 0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppCard(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(loan.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                              Text('${loan.type == 'expense' ? 'خرید اعتباری' : 'وام نقدی'}${la != null ? ' · ${la.name}' : (cat != null ? ' · ${cat.name}' : '')}',
                                  style: const TextStyle(fontSize: 11, color: C.slate500)),
                            ]),
                          ),
                          Text('$paid/$total تسویه', style: const TextStyle(fontSize: 11, color: C.slate400)),
                        ]),
                        const SizedBox(height: 10),
                        Row(children: [
                          const Expanded(child: Text('پیشرفت تسویه', style: TextStyle(fontSize: 10, color: C.slate500))),
                          Text('${toPersianDigits(pct)}٪', style: const TextStyle(fontSize: 10, color: C.slate400)),
                        ]),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(value: (pct > 0 ? (pct < 4 ? 4 : pct) : 0) / 100, minHeight: 5, backgroundColor: C.white5, color: C.purple500),
                        ),
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(child: StatPill(label: loan.assetId != null ? 'مقدار هر قسط' : 'مبلغ هر قسط', value: _formatLoanQty(s, assetsById, loan.installmentAmount, loan))),
                          const SizedBox(width: 8),
                          Expanded(child: StatPill(label: 'جمع کل', value: _formatLoanQty(s, assetsById, totalDisplay, loan))),
                        ]),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                            child: AppButton('ویرایش', dense: true, variant: BtnVariant.secondary, expand: true, onPressed: () async {
                              await Nav.push(context, '/deadlines/loans/${loan.id}/edit');
                              _refresh();
                            }),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: AppButton('حذف', icon: Icons.delete_outline, dense: true, variant: BtnVariant.danger, expand: true, onPressed: submitting ? null : () => _deleteLoan(loan))),
                        ]),
                      ]),
                    ),
                  );
                }),
            ],
          ] else if (tab == 'installments') ...[
            if (rows.isEmpty)
              const EmptyState(title: 'قسطی برای نمایش نیست.', description: 'بعد از ثبت وام، برنامه اقساط اینجا نمایش داده می‌شود.')
            else ...[
              AppCard(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  const Expanded(child: Text('جمع باقی‌مانده', style: TextStyle(fontSize: 12, color: C.slate400))),
                  Money(formatCurrency(remainingDisplay, s.currencyMode), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: C.amber300)),
                ]),
              ),
              const SizedBox(height: 10),
              _filterChips(const [('all', 'همه'), ('paid', 'تسویه شده'), ('remaining', 'باقی‌مانده')], installmentFilter, (v) => setState(() => installmentFilter = v)),
              const SizedBox(height: 12),
              if (groups.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('موردی با این فیلتر وجود ندارد.', textAlign: TextAlign.center, style: TextStyle(color: C.slate500, fontSize: 12))),
              for (final g in groups.values) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 8),
                  child: Row(children: [
                    Expanded(child: Text(g.$1, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: C.slate300))),
                    Money(formatCurrency(g.$3, s.currencyMode), style: const TextStyle(fontSize: 12, color: C.slate400)),
                  ]),
                ),
                for (final r in g.$2) _installmentCard(s, assetsById, r, meta),
              ],
            ],
          ] else ...[
            AppCard(
              child: Column(children: [
                Row(children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_right, size: 20, color: C.slate300),
                    onPressed: () => setState(() {
                      if (calM == 1) {
                        calY--;
                        calM = 12;
                      } else {
                        calM--;
                      }
                    }),
                  ),
                  Expanded(
                    child: Column(children: [
                      Text('${kJalaliMonths[calM - 1]} ${toPersianDigits(calY)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                      Text('جمع بدهی ماه: ${formatCurrency(monthRows.fold<double>(0.0, (a, r) => a + _displayAmount(s, assetsById, r)), s.currencyMode)}',
                          style: const TextStyle(fontSize: 11, color: C.slate400)),
                    ]),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_left, size: 20, color: C.slate300),
                    onPressed: () => setState(() {
                      if (calM == 12) {
                        calY++;
                        calM = 1;
                      } else {
                        calM++;
                      }
                    }),
                  ),
                ]),
                const SizedBox(height: 8),
                GridView.count(
                  crossAxisCount: 7,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                  childAspectRatio: 0.9,
                  children: [
                    for (final l in _weekdayShort) Center(child: Text(l, style: const TextStyle(fontSize: 11, color: C.slate500))),
                    for (var i = 0; i < firstWd; i++) const SizedBox.shrink(),
                    for (var d = 1; d <= monthLen; d++)
                      Builder(builder: (_) {
                        final date = '$monthKey/${d.toString().padLeft(2, '0')}';
                        final cr = byDate[date] ?? const [];
                        final selected = selectedDate == date;
                        final overdue = cr.isNotEmpty && date.compareTo(todayS) < 0;
                        return GestureDetector(
                          onTap: () => setState(() => selectedDate = date),
                          child: Container(
                            decoration: BoxDecoration(
                              color: selected ? C.purple.withValues(alpha: 0.3) : (cr.isNotEmpty ? C.amber.withValues(alpha: 0.08) : const Color(0x08FFFFFF)),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: selected ? C.purple500.withValues(alpha: 0.6) : (cr.isNotEmpty ? C.amber.withValues(alpha: 0.3) : C.borderSoft)),
                            ),
                            child: Stack(alignment: Alignment.center, children: [
                              Text(toPersianDigits(d), style: TextStyle(fontSize: 12, color: selected ? Colors.white : C.slate300, fontWeight: selected ? FontWeight.w700 : FontWeight.w400)),
                              if (cr.isNotEmpty)
                                Positioned(
                                  bottom: 2,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    decoration: BoxDecoration(color: (overdue ? C.rose : C.amber).withValues(alpha: 0.2), borderRadius: BorderRadius.circular(999)),
                                    child: Text(toPersianDigits(cr.length), style: TextStyle(fontSize: 9, color: overdue ? C.rose300 : C.amber300)),
                                  ),
                                ),
                              if (date == todayS) Positioned(top: 3, child: Container(width: 4, height: 4, decoration: const BoxDecoration(color: C.purple400, shape: BoxShape.circle))),
                            ]),
                          ),
                        );
                      }),
                  ],
                ),
              ]),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: Text(sp != null && sp.jy == calY && sp.jm == calM ? formatJalaaliHuman(sp) : (parseJalaali(selectedDate) != null ? formatJalaaliHuman(parseJalaali(selectedDate)!) : selectedDate), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: C.slate200))),
              Money(formatCurrency(dayRows.fold<double>(0.0, (a, r) => a + _displayAmount(s, assetsById, r)), s.currencyMode), style: const TextStyle(fontSize: 12, color: C.slate400)),
            ]),
            const SizedBox(height: 8),
            if (dayRows.isEmpty)
              const Text('برای این روز قسطی ثبت نشده.', style: TextStyle(fontSize: 12, color: C.slate500))
            else
              for (final r in dayRows) _installmentCard(s, assetsById, r, meta, showDate: false, settleOnly: true),
          ],
        ]),
      ),
    );
  }
}

class _SettleSheet extends StatefulWidget {
  final LoanInstallment installment;
  final Loan loan;
  final PortfolioStore store;
  final Future<void> Function() onDone;
  const _SettleSheet({required this.installment, required this.loan, required this.store, required this.onDone});
  @override
  State<_SettleSheet> createState() => _SettleSheetState();
}

class _SettleSheetState extends State<_SettleSheet> {
  String? walletId;
  late String payAmount = canonicalInstallmentAmount(installmentRemainingAmount(widget.installment));
  bool submitting = false;

  bool get assetLoan => widget.loan.assetId != null;

  @override
  void initState() {
    super.initState();
    if (!assetLoan) WidgetsBinding.instance.addPostFrameCallback((_) => _pickWallet());
  }

  Future<void> _pickWallet() async {
    final s = widget.store;
    final r = await showListPicker(context,
        title: 'انتخاب کیف پول پرداخت',
        items: [for (final w in s.wallets) PickItem(id: w.id, label: w.name, sublabel: '${currencyMeta(w.currency).label} · ${w.currency}')],
        value: walletId);
    if (r != null && r != kNone) setState(() => walletId = r);
  }

  Future<void> _settle() async {
    final s = widget.store;
    final it = widget.installment;
    final loan = widget.loan;
    final asset = assetLoan ? findAsset(s.assets, loan.assetId) : null;
    final wallet = assetLoan ? null : findWallet(s.wallets, walletId);
    if (!assetLoan && wallet == null) {
      Toast.error('کیف پول پرداخت را انتخاب کن.');
      return;
    }
    if (assetLoan && asset == null) {
      Toast.error('دارایی وام پیدا نشد.');
      return;
    }
    final remaining = installmentRemainingAmount(it);
    final raw = payAmount.trim().replaceAll(',', '');
    final pay = raw.isEmpty ? null : double.tryParse(raw);
    if (pay == null || !pay.isFinite || pay <= 0) {
      Toast.error(assetLoan ? 'مقدار پرداخت نامعتبر است.' : 'مبلغ پرداخت نامعتبر است.');
      return;
    }
    final amountErr = validatePartialPayAmount(pay, remaining);
    if (amountErr != null) {
      Toast.error(amountErr);
      return;
    }
    final snapUsd = usdRateOn(s.rateHistories, it.dueDateString, todayStr(), s.usdRate);
    Json payload;
    if (assetLoan && asset != null) {
      final p = asset.priceToman;
      if (!(p > 0) || !(s.usdRate > 0)) {
        Toast.error('قیمت دارایی برای تسویه در دسترس نیست.');
        return;
      }
      payload = {
        'user_id': s.user?.id,
        'type': 'EXPENSE',
        'date_string': it.dueDateString,
        'note': loan.title,
        'source_wallet_id': null,
        'source_asset_id': asset.id,
        'target_wallet_id': null,
        'target_asset_id': null,
        'source_amount': pay,
        'target_amount': null,
        'category_id': loan.type == 'expense' ? loan.categoryId : null,
        'asset_id': asset.id,
        'amount': pay,
        'price_toman': p,
        'usd_rate': snapUsd,
        'amount_toman_at_time': pay * p,
        'amount_usd_at_time': pay * p / snapUsd,
      };
    } else {
      final loanRate = tomanPerUnit(loan.currency, s.currencyRates);
      final payRate = tomanPerUnit(wallet!.currency, s.currencyRates);
      if (loanRate <= 0 || payRate <= 0 || s.usdRate <= 0) {
        Toast.error('نرخ تبدیل برای تسویه در دسترس نیست.');
        return;
      }
      final amt = pay * loanRate / payRate;
      if (!amt.isFinite || amt <= 0) {
        Toast.error('مبلغ تسویه نامعتبر است.');
        return;
      }
      payload = {
        'user_id': s.user?.id,
        'type': 'EXPENSE',
        'date_string': it.dueDateString,
        'note': loan.title,
        'source_wallet_id': wallet.id,
        'source_asset_id': null,
        'target_wallet_id': null,
        'target_asset_id': null,
        'source_amount': amt,
        'target_amount': null,
        'category_id': loan.type == 'expense' ? loan.categoryId : null,
        'asset_id': null,
        'amount': null,
        'price_toman': wallet.currency == 'IRT' ? null : payRate,
        'usd_rate': wallet.currency == 'IRT' ? null : snapUsd,
        'amount_toman_at_time': amt * payRate,
        'amount_usd_at_time': amt * payRate / snapUsd,
      };
    }
    setState(() => submitting = true);
    final c = Supabase.instance.client;
    try {
      final txData = await c.from('transactions').insert(payload).select().single();
      final created = Transaction.fromJson(txData);
      final newPaid = installmentPaidAmount(it) + pay;
      final fully = newPaid >= it.amount - 1e-9;
      List updated;
      try {
        updated = await c
            .from('loan_installments')
            .update({
              'paid_amount': newPaid,
              'is_paid': fully,
              'paid_at': fully ? DateTime.now().toUtc().toIso8601String() : it.paidAt,
              'paid_transaction_id': created.id,
            })
            .eq('id', it.id)
            .eq('is_paid', false)
            .eq('paid_amount', installmentPaidAmount(it))
            .select('id');
      } catch (e) {
        await c.from('transactions').delete().eq('id', created.id);
        rethrow;
      }
      if (updated.isEmpty) {
        await c.from('transactions').delete().eq('id', created.id);
        Toast.error('این قسط هم‌زمان تغییر کرد. صفحه را تازه کن و دوباره تلاش کن.');
        if (mounted) Navigator.pop(context);
        await widget.onDone();
        return;
      }
      s.update((st) => st.transactions = [created, ...st.transactions]);
      Api.fireExpenseAlert([created.id]);
      Toast.success(fully ? 'قسط تسویه شد و تراکنش ثبت شد.' : 'پرداخت جزئی ثبت شد.');
      if (mounted) Navigator.pop(context);
      await widget.onDone();
    } catch (_) {
      Toast.error('خطا در تسویه قسط.');
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final asset = assetLoan ? findAsset(s.assets, widget.loan.assetId) : null;
    final unit = assetLoan ? (asset?.unit ?? 'واحد') : currencyMeta(widget.loan.currency).label;
    final remaining = installmentRemainingAmount(widget.installment);
    final wallet = findWallet(s.wallets, walletId);
    final canSubmit = assetLoan ? payAmount.trim().isNotEmpty : walletId != null && payAmount.trim().isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(widget.loan.title, style: const TextStyle(fontSize: 13, color: C.slate300)),
      const SizedBox(height: 12),
      Field(label: assetLoan ? 'مقدار پرداخت ($unit)' : 'مبلغ پرداخت ($unit)', child: NumberInput(value: payAmount, onChanged: (v) => setState(() => payAmount = v), enabled: !submitting)),
      Money('باقی‌مانده: ${canonicalInstallmentAmount(remaining)} $unit${asset != null ? ' · ${asset.name}' : ''}', style: const TextStyle(fontSize: 11, color: C.slate500)),
      const SizedBox(height: 14),
      if (!assetLoan) ...[
        SelectBox(text: wallet?.name ?? 'کیف پول', placeholder: wallet == null, leading: const Icon(Icons.account_balance_wallet_outlined, size: 16, color: C.slate400), onTap: submitting ? null : _pickWallet),
        const SizedBox(height: 10),
      ],
      Row(children: [
        Expanded(
          child: AppButton(
            submitting ? 'در حال تسویه...' : (assetLoan ? (asset != null ? 'ثبت با ${asset.name}' : 'ثبت پرداخت') : (wallet != null ? 'ثبت با ${wallet.name}' : 'ثبت پرداخت')),
            expand: true,
            loading: submitting,
            onPressed: submitting || !canSubmit ? null : _settle,
          ),
        ),
        const SizedBox(width: 8),
        AppButton('انصراف', variant: BtnVariant.secondary, onPressed: () => Navigator.pop(context)),
      ]),
    ]);
  }
}

// ─── Loan form ──────────────────────────────────────────────────────────────

class LoanFormScreen extends StatefulWidget {
  final String? loanId;
  const LoanFormScreen({super.key, this.loanId});
  @override
  State<LoanFormScreen> createState() => _LoanFormScreenState();
}

class _LoanFormScreenState extends State<LoanFormScreen> {
  String title = '', type = 'expense', denomination = 'currency';
  String? categoryId, currencyWalletId, assetId, autoIncomeWalletId;
  String totalAmount = '', installmentAmount = '', description = '', repeatCount = '12', intervalNumber = '1', intervalPeriod = 'month';
  late String loanStartDate = todayStr(), firstDueDate = todayStr();
  bool autoIncome = false, submitting = false;
  late bool loading = widget.loanId != null;
  List<int> reminderDays = [3];
  int formKey = 0;

  bool get isEdit => widget.loanId != null;

  @override
  void initState() {
    super.initState();
    if (isEdit) _load();
  }

  Future<void> _load() async {
    try {
      final data = await Supabase.instance.client.from('loans').select().eq('id', widget.loanId!).single();
      final l = Loan.fromJson(data);
      setState(() {
        title = l.title;
        type = l.type;
        denomination = l.assetId != null ? 'asset' : 'currency';
        categoryId = l.categoryId;
        assetId = l.assetId;
        totalAmount = l.totalAmount != null ? jsNumStr(l.totalAmount) : '';
        installmentAmount = jsNumStr(l.installmentAmount);
        loanStartDate = l.loanStartDateString;
        firstDueDate = l.firstDueDateString;
        description = l.description ?? '';
        repeatCount = '${l.repeatCount}';
        intervalNumber = '${l.intervalNumber}';
        intervalPeriod = l.intervalPeriod;
        autoIncome = l.autoIncomeOnCreate;
        autoIncomeWalletId = l.autoIncomeWalletId;
        reminderDays = normalizeReminderDaysBefore(l.reminderDaysBefore);
        formKey++;
      });
    } catch (_) {
      Toast.error('خطا در دریافت اطلاعات وام.');
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String? _validateCreate(PortfolioStore s) {
    if (title.trim().isEmpty) return 'عنوان الزامی است.';
    if (parseJalaali(loanStartDate) == null) return 'تاریخ شروع وام نامعتبر است.';
    if (parseJalaali(firstDueDate) == null) return 'تاریخ اولین قسط نامعتبر است.';
    if (denomination == 'currency' && currencyWalletId == null) return 'کیف پول مبنا برای تعیین ارز وام الزامی است.';
    if (denomination == 'asset' && assetId == null) return 'انتخاب دارایی وام الزامی است.';
    if (type == 'expense' && categoryId == null) return 'انتخاب دسته هزینه الزامی است.';
    final ia = n(installmentAmount), rc = n(repeatCount), inum = n(intervalNumber);
    if (!ia.isFinite || ia <= 0) return denomination == 'asset' ? 'مقدار هر قسط نامعتبر است.' : 'مبلغ هر قسط نامعتبر است.';
    if (!rc.isFinite || rc <= 0 || rc != rc.truncateToDouble()) return 'تعداد اقساط نامعتبر است.';
    if (!inum.isFinite || inum <= 0 || inum != inum.truncateToDouble()) return 'فاصله تکرار نامعتبر است.';
    if (type == 'loan' && autoIncome && denomination == 'currency' && autoIncomeWalletId == null) return 'برای تراکنش خودکار، کیف پول دریافت را انتخاب کن.';
    if (type == 'loan' && autoIncome && denomination == 'asset') {
      final a = findAsset(s.assets, assetId);
      if (a == null || !(a.priceToman > 0)) return 'برای ثبت خودکار، قیمت دارایی باید تنظیم شده باشد.';
      if (!(s.usdRate > 0)) return 'نرخ دلار برای ثبت خودکار در دسترس نیست.';
    }
    return null;
  }

  Future<void> _submit(PortfolioStore s) async {
    final user = s.user;
    if (user == null) {
      Toast.error('کاربر معتبر نیست.');
      return;
    }
    final c = Supabase.instance.client;
    if (isEdit) {
      if (title.trim().isEmpty) {
        Toast.error('عنوان الزامی است.');
        return;
      }
      setState(() => submitting = true);
      try {
        await c.from('loans').update({
          'title': title.trim(),
          'description': description.trim().isEmpty ? null : description.trim(),
          'reminder_days_before': normalizeReminderDaysBefore(reminderDays),
        }).eq('id', widget.loanId!);
        Toast.success('وام ویرایش شد.');
        if (mounted) Navigator.pop(context);
      } catch (_) {
        Toast.error('خطا در ویرایش وام.');
      } finally {
        if (mounted) setState(() => submitting = false);
      }
      return;
    }
    final err = _validateCreate(s);
    if (err != null) {
      Toast.error(err);
      return;
    }
    final rc = n(repeatCount).toInt();
    final inum = n(intervalNumber).toInt();
    final ia = n(installmentAmount);
    final total = type == 'loan' && totalAmount.trim().isNotEmpty ? n(totalAmount) : ia * rc;
    final isAsset = denomination == 'asset';
    final baseWallet = isAsset ? null : findWallet(s.wallets, currencyWalletId);
    final loanAsset = isAsset ? findAsset(s.assets, assetId) : null;
    final schedule = buildInstallmentSchedule(firstDueDate: firstDueDate, repeatCount: rc, intervalNumber: inum, intervalPeriod: intervalPeriod);
    if (schedule.length != rc) {
      Toast.error('برنامه اقساط قابل تولید نیست.');
      return;
    }
    setState(() => submitting = true);
    try {
      final loanData = await c
          .from('loans')
          .insert({
            'user_id': user.id,
            'title': title.trim(),
            'type': type,
            'category_id': type == 'expense' ? categoryId : null,
            'currency': isAsset ? 'IRT' : baseWallet!.currency,
            'asset_id': isAsset ? assetId : null,
            'installment_amount': ia,
            'total_amount': total.isFinite ? total : null,
            'loan_start_date_string': loanStartDate,
            'first_due_date_string': firstDueDate,
            'repeat_count': rc,
            'interval_number': inum,
            'interval_period': intervalPeriod,
            'auto_income_on_create': type == 'loan' && autoIncome && !isAsset,
            'auto_income_wallet_id': type == 'loan' && autoIncome && !isAsset ? autoIncomeWalletId : null,
            'description': description.trim().isEmpty ? null : description.trim(),
            'reminder_days_before': normalizeReminderDaysBefore(reminderDays),
            'deleted_at': null,
          })
          .select()
          .single();
      final loan = Loan.fromJson(loanData);
      try {
        await c.from('loan_installments').insert([
          for (var i = 0; i < schedule.length; i++)
            {
              'user_id': user.id,
              'loan_id': loan.id,
              'due_date_string': schedule[i],
              'amount': ia,
              'sequence_no': i + 1,
              'is_paid': false,
              'paid_at': null,
              'paid_transaction_id': null,
            }
        ]);
      } catch (e) {
        await c.from('loans').delete().eq('id', loan.id);
        rethrow;
      }
      if (type == 'loan' && autoIncome) {
        final incomeUsd = usdRateOn(s.rateHistories, loanStartDate, todayStr(), s.usdRate);
        Json? tx;
        if (isAsset && loanAsset != null) {
          final qty = total, p = loanAsset.priceToman;
          tx = {
            'user_id': user.id,
            'type': 'INCOME',
            'date_string': loanStartDate,
            'note': 'وام: ${title.trim()}',
            'source_wallet_id': null,
            'source_asset_id': null,
            'target_wallet_id': null,
            'target_asset_id': loanAsset.id,
            'source_amount': null,
            'target_amount': qty,
            'category_id': null,
            'asset_id': loanAsset.id,
            'amount': qty,
            'price_toman': p,
            'usd_rate': incomeUsd,
            'amount_toman_at_time': qty * p,
            'amount_usd_at_time': incomeUsd > 0 ? qty * p / incomeUsd : null,
          };
        } else if (autoIncomeWalletId != null) {
          final w = findWallet(s.wallets, autoIncomeWalletId);
          if (w != null) {
            final rate = tomanPerUnit(w.currency, s.currencyRates);
            tx = {
              'user_id': user.id,
              'type': 'INCOME',
              'date_string': loanStartDate,
              'note': 'وام: ${title.trim()}',
              'source_wallet_id': null,
              'source_asset_id': null,
              'target_wallet_id': w.id,
              'target_asset_id': null,
              'source_amount': null,
              'target_amount': total,
              'category_id': null,
              'asset_id': null,
              'amount': null,
              'price_toman': w.currency == 'IRT' ? null : rate,
              'usd_rate': w.currency == 'IRT' ? null : incomeUsd,
              'amount_toman_at_time': total * rate,
              'amount_usd_at_time': incomeUsd > 0 ? total * rate / incomeUsd : null,
            };
          }
        }
        if (tx != null) {
          final d = await c.from('transactions').insert(tx).select().single();
          s.update((st) => st.transactions = [Transaction.fromJson(d), ...st.transactions]);
        }
      }
      Toast.success('وام با برنامه اقساط ثبت شد.');
      if (mounted) Navigator.pop(context);
    } catch (_) {
      Toast.error('خطا در ثبت وام.');
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<String?> _pickWallet(PortfolioStore s, String title, String? value) async {
    final r = await showListPicker(context,
        title: title, items: [for (final w in s.wallets) PickItem(id: w.id, label: w.name, sublabel: '${currencyMeta(w.currency).label} · ${w.currency}')], value: value);
    return r == kNone ? null : r;
  }

  Widget _dateBox(String label, String value, ValueChanged<String> onChanged) => Opacity(
        opacity: isEdit ? 0.6 : 1,
        child: Field(
          label: label,
          child: SelectBox(
            text: parseJalaali(value) != null ? formatJalaaliHuman(parseJalaali(value)!) : value,
            leading: const Icon(Icons.calendar_today_outlined, size: 16, color: C.purple400),
            trailing: Icons.chevron_left,
            onTap: isEdit
                ? null
                : () async {
                    final r = await showJalaliDatePicker(context, value);
                    if (r != null) onChanged(r);
                  },
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = context.watch<PortfolioStore>();
    if (loading) return SubPage(title: isEdit ? 'ویرایش وام' : 'ثبت وام جدید', body: const Center(child: Text('در حال دریافت...', style: TextStyle(color: C.slate500))));
    final cw = findWallet(s.wallets, currencyWalletId);
    final sa = findAsset(s.assets, assetId);
    final aw = findWallet(s.wallets, autoIncomeWalletId);
    final unitLabel = denomination == 'asset' && sa != null ? sa.unit : null;
    final pc = n(repeatCount), pi = n(intervalNumber);
    final preview = pc > 0 && pc <= 3 && pi > 0 && parseJalaali(firstDueDate) != null
        ? buildInstallmentSchedule(firstDueDate: firstDueDate, repeatCount: pc.toInt(), intervalNumber: pi.toInt(), intervalPeriod: intervalPeriod)
        : const <String>[];
    return SubPage(
      title: isEdit ? 'ویرایش وام' : 'ثبت وام جدید',
      body: ListView(key: ValueKey(formKey), padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
        Field(label: 'عنوان', child: AppTextField(value: title, onChanged: (v) => title = v, hint: 'مثال: خرید لپ‌تاپ')),
        Field(
          label: 'نوع وام',
          child: IgnorePointer(
            ignoring: isEdit,
            child: Opacity(
              opacity: isEdit ? 0.6 : 1,
              child: Segmented<String>(options: const [('expense', 'خرید اعتباری'), ('loan', 'وام نقدی')], value: type, onChanged: (v) => setState(() => type = v)),
            ),
          ),
        ),
        if (!isEdit)
          Field(
            label: 'واحد وام',
            child: Segmented<String>(
              options: const [('currency', 'ارز'), ('asset', 'دارایی')],
              value: denomination,
              onChanged: (v) => setState(() {
                denomination = v;
                if (v == 'currency') {
                  assetId = null;
                  autoIncome = false;
                } else {
                  currencyWalletId = null;
                }
                autoIncomeWalletId = null;
              }),
            ),
          ),
        if (!isEdit && denomination == 'currency')
          Field(
            label: 'کیف پول مبنا (ارز وام)',
            child: SelectBox(
              text: cw != null ? '${cw.name} · ${cw.currency}' : 'انتخاب کنید',
              placeholder: cw == null,
              trailing: Icons.chevron_left,
              onTap: () async {
                final r = await _pickWallet(s, 'انتخاب کیف پول مبنا', currencyWalletId);
                if (r != null) setState(() => currencyWalletId = r);
              },
            ),
          ),
        if (!isEdit && denomination == 'asset')
          Field(
            label: 'دارایی وام',
            child: SelectBox(
              text: sa != null ? '${sa.name} · ${sa.unit}' : 'انتخاب کنید',
              placeholder: sa == null,
              trailing: Icons.chevron_left,
              onTap: () async {
                final r = await showListPicker(context, title: 'انتخاب دارایی وام', items: [for (final a in s.assets) PickItem(id: a.id, label: a.name, sublabel: a.unit)], value: assetId);
                if (r != null && r != kNone) setState(() => assetId = r);
              },
            ),
          ),
        if (isEdit && denomination == 'asset' && sa != null) Field(label: 'دارایی وام', child: Text('${sa.name} · ${sa.unit}', style: const TextStyle(color: C.slate200))),
        if (type == 'expense')
          Field(
            label: 'دسته هزینه',
            child: Opacity(
              opacity: isEdit ? 0.6 : 1,
              child: SelectBox(
                text: s.categories.where((c) => c.id == categoryId && c.kind == 'expense').firstOrNull?.name ?? 'انتخاب کنید',
                placeholder: categoryId == null,
                trailing: Icons.chevron_left,
                onTap: isEdit
                    ? null
                    : () async {
                        final r = await showCategoryPicker(context, title: 'انتخاب دسته هزینه', kind: 'expense', categories: s.categories, value: categoryId);
                        if (r != null && r != kNone) setState(() => categoryId = r);
                      },
              ),
            ),
          ),
        if (type == 'loan') ...[
          Field(
            label: denomination == 'asset' ? 'مقدار کل وام${unitLabel != null ? ' ($unitLabel)' : ''}' : 'مبلغ کل وام',
            child: NumberInput(value: totalAmount, onChanged: (v) => totalAmount = v, enabled: !isEdit),
          ),
          if (!isEdit) ...[
            SwitchRow(
              title: denomination == 'asset' ? 'ثبت دریافت دارایی خودکار' : 'ثبت تراکنش درآمد خودکار',
              value: autoIncome,
              onChanged: (v) => setState(() {
                autoIncome = v;
                if (!v) autoIncomeWalletId = null;
              }),
            ),
            if (autoIncome && denomination == 'currency')
              Field(
                label: 'کیف پول دریافت',
                child: SelectBox(
                  text: aw != null ? '${aw.name} · ${aw.currency}' : 'انتخاب کنید',
                  placeholder: aw == null,
                  trailing: Icons.chevron_left,
                  onTap: () async {
                    final r = await _pickWallet(s, 'انتخاب کیف پول دریافت', autoIncomeWalletId);
                    if (r != null) setState(() => autoIncomeWalletId = r);
                  },
                ),
              ),
            if (autoIncome && denomination == 'asset')
              const Padding(padding: EdgeInsets.only(bottom: 12), child: Text('کل مقدار وام به‌صورت درآمد روی همین دارایی ثبت می‌شود.', style: TextStyle(fontSize: 11, color: C.slate400))),
          ],
        ],
        Field(
          label: denomination == 'asset' ? 'مقدار هر قسط${unitLabel != null ? ' ($unitLabel)' : ''}' : 'مبلغ هر قسط',
          child: NumberInput(value: installmentAmount, onChanged: (v) => installmentAmount = v, enabled: !isEdit),
        ),
        _dateBox('تاریخ شروع وام', loanStartDate, (v) => setState(() => loanStartDate = v)),
        _dateBox('تاریخ اولین قسط', firstDueDate, (v) => setState(() => firstDueDate = v)),
        Row(children: [
          Expanded(child: Field(label: 'تعداد اقساط', child: NumberInput(value: repeatCount, onChanged: (v) => setState(() => repeatCount = v), enabled: !isEdit))),
          const SizedBox(width: 10),
          Expanded(child: Field(label: 'فاصله تکرار', child: NumberInput(value: intervalNumber, onChanged: (v) => setState(() => intervalNumber = v), enabled: !isEdit))),
        ]),
        Field(
          label: 'واحد فاصله',
          child: IgnorePointer(
            ignoring: isEdit,
            child: Opacity(
              opacity: isEdit ? 0.6 : 1,
              child: Segmented<String>(options: [for (final e in kIntervalLabels.entries) (e.key, e.value)], value: intervalPeriod, onChanged: (v) => setState(() => intervalPeriod = v)),
            ),
          ),
        ),
        ReminderDaysField(value: reminderDays, onChanged: (v) => setState(() => reminderDays = v)),
        if (preview.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: AppCard(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('پیش‌نمایش سررسیدها', style: TextStyle(fontSize: 12, color: C.slate400)),
                for (final d in preview) Text(parseJalaali(d) != null ? formatJalaaliHuman(parseJalaali(d)!) : d, style: const TextStyle(fontSize: 12, color: C.slate200)),
              ]),
            ),
          ),
        Field(label: 'توضیحات', child: AppTextField(value: description, onChanged: (v) => description = v, maxLines: 3)),
        AppButton(submitting ? 'در حال ثبت...' : (isEdit ? 'ثبت تغییرات' : 'ایجاد وام'), expand: true, onPressed: submitting ? null : () => _submit(s)),
        if (isEdit)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text('بعد از ثبت وام فقط عنوان، توضیحات و یادآوری‌ها قابل ویرایش است.', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: C.slate500)),
          ),
      ]),
    );
  }
}

class ReminderDaysField extends StatelessWidget {
  final List<int> value;
  final ValueChanged<List<int>> onChanged;
  const ReminderDaysField({super.key, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => Field(
        label: 'یادآوری تلگرام قبل از سررسید',
        hint: 'علاوه بر پیام روز سررسید، در این فاصله‌ها هم یادآوری می‌گیرید.',
        child: Wrap(spacing: 6, runSpacing: 6, children: [
          for (final d in kLoanReminderDayOptions)
            FilterChipX(
              active: value.contains(d),
              label: '$d روز قبل',
              onTap: () => onChanged(value.contains(d) ? value.where((x) => x != d).toList() : normalizeReminderDaysBefore([...value, d])),
            ),
        ]),
      );
}
