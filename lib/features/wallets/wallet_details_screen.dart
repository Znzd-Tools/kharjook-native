// Port of WalletDetailsView.tsx, WalletSavingsPotsSection.tsx,
// WalletPaymentDetailsSheet.tsx, CopyableDetailRow.tsx, wallet utils.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/router.dart';
import '../../core/logic/ledger.dart';
import '../../core/models.dart';
import '../../core/store.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/toast.dart';
import '../../core/ui/widgets.dart';
import '../../core/utils/digits.dart';
import '../../core/utils/format.dart';
import '../transactions/endpoint_picker.dart';
import '../transactions/history_widgets.dart';
import '../transactions/tx_logic.dart';

const kCategoryColors = ['#8b5cf6', '#3b82f6', '#10b981', '#f59e0b', '#ef4444', '#ec4899', '#6366f1', '#14b8a6'];

String formatCardGroups(String v) => v.replaceAll(RegExp(r'\D'), '').replaceAllMapped(RegExp(r'(.{4})'), (m) => '${m[1]} ').trim();

String formatIban(String v) {
  final raw = v.replaceAll(RegExp(r'\s'), '').toUpperCase();
  if (raw.isEmpty) return '';
  final prefix = raw.startsWith('IR') ? 'IR' : '';
  final body = prefix.isNotEmpty ? raw.substring(2) : raw;
  final grouped = body.replaceAllMapped(RegExp(r'(.{4})'), (m) => '${m[1]} ').trim();
  return prefix.isNotEmpty ? '$prefix${grouped.isNotEmpty ? ' $grouped' : ''}' : grouped;
}

bool walletHasPaymentDetails(Wallet w) =>
    (w.cardNumber ?? '').isNotEmpty || (w.accountNumber ?? '').isNotEmpty || (w.iban ?? '').isNotEmpty || (w.accountOwnerName ?? '').isNotEmpty;

Future<void> undoTransactionDelete(PortfolioStore s, Transaction tx) async {
  final created = DateTime.tryParse(tx.createdAt);
  if (created == null || DateTime.now().difference(created).inMilliseconds > 5 * 60 * 1000) {
    Toast.error('مهلت ۵ دقیقه‌ای لغو تمام شده.');
    return;
  }
  final row = tx.toJson()
    ..remove('id')
    ..remove('created_at');
  try {
    final data = await Supabase.instance.client.from('transactions').insert([row]).select().single();
    s.update((st) => st.transactions = [Transaction.fromJson(data), ...st.transactions]);
    Toast.info('تراکنش بازگردانده شد.');
  } catch (_) {
    Toast.error('بازگردانی تراکنش ناموفق بود.');
  }
}

class WalletDetailsScreen extends StatefulWidget {
  final String walletId;
  const WalletDetailsScreen({super.key, required this.walletId});
  @override
  State<WalletDetailsScreen> createState() => _WalletDetailsScreenState();
}

class _WalletDetailsScreenState extends State<WalletDetailsScreen> {
  String typeFilter = 'ALL';
  String query = '';

  Future<void> _deleteTx(PortfolioStore s, String id) async {
    if (!await confirmDialog(context, message: 'آیا از حذف این تراکنش مطمئن هستید؟', danger: true, confirmLabel: 'حذف')) return;
    final snap = s.transactions.where((t) => t.id == id).firstOrNull;
    if (snap == null) return;
    try {
      await Supabase.instance.client.from('transactions').delete().eq('id', id);
      s.update((st) => st.transactions = st.transactions.where((t) => t.id != id).toList());
      Toast.success('تراکنش حذف شد.', durationMs: 8000, actionLabel: 'بازگردانی', onAction: () => undoTransactionDelete(s, snap));
    } catch (_) {
      Toast.error('خطا در حذف رکورد.');
    }
  }

  Future<void> _deleteConvert(PortfolioStore s, ConvertGroup g) async {
    if (!await confirmDialog(context, message: 'آیا از حذف این تبدیل (فروش + خرید) مطمئن هستید؟', danger: true, confirmLabel: 'حذف')) return;
    try {
      await Supabase.instance.client.from('transactions').delete().inFilter('id', [g.sell.id, g.buy.id]);
      s.update((st) => st.transactions = st.transactions.where((t) => t.id != g.sell.id && t.id != g.buy.id).toList());
    } catch (_) {
      Toast.error('خطا در حذف تبدیل.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<PortfolioStore>();
    final wallet = findWallet(s.wallets, widget.walletId);
    if (wallet == null) return const SubPage(title: 'کیف پول', body: Center(child: Text('کیف پول پیدا نشد.', style: TextStyle(color: C.slate400))));
    final mode = s.currencyMode;
    final stats = calculateWalletStats(wallet, s.transactions);
    final meta = currencyMeta(wallet.currency);
    final rate = walletRateNow(wallet.currency, s.currencyRates, s.rateHistories).rate;
    final bt = stats.balance * rate;
    final bd = mode == 'USD' && s.usdRate > 0 ? bt / s.usdRate : bt;
    final visible = typeFilter == 'ALL' ? stats.transactions : stats.transactions.where((t) => t.type == typeFilter).toList();
    final groups = convertGroupsForWallet(wallet.id, groupConvertTransactions(s.transactions));
    final convertIds = transactionIdsInConvertGroups(s.transactions);
    final lookup = HistoryLookup(s.wallets, s.assets, s.categories);
    final items = <(String, ConvertGroup?, Transaction?)>[];
    for (final g in groups) {
      if (typeFilter != 'ALL') {
        final ok = (typeFilter == 'SELL' && g.sell.targetWalletId == wallet.id) || (typeFilter == 'BUY' && g.buy.sourceWalletId == wallet.id);
        if (!ok) continue;
      }
      if (!convertGroupMatchesSearch(g, query, lookup)) continue;
      items.add((g.sell.dateString, g, null));
    }
    for (final t in visible) {
      if (convertIds.contains(t.id) || !transactionMatchesSearch(t, query, lookup)) continue;
      items.add((t.dateString, null, t));
    }
    final sorted = stableSorted(items, (a, b) => b.$1.compareTo(a.$1));
    final hasDetails = walletHasPaymentDetails(wallet);

    return SubPage(
      title: wallet.name,
      bottom: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(children: [
            Expanded(
                child: AppButton('انتقال',
                    icon: Icons.swap_horiz, variant: BtnVariant.secondary, expand: true, onPressed: () => Nav.push(context, '/transactions/new?walletId=${wallet.id}&type=TRANSFER'))),
            const SizedBox(width: 10),
            Expanded(child: AppButton('تراکنش جدید', icon: Icons.add, expand: true, onPressed: () => Nav.push(context, '/transactions/new?walletId=${wallet.id}'))),
          ]),
        ),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        AppCard(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: C.white5, borderRadius: BorderRadius.circular(999)),
                child: Money('${meta.symbol} ${wallet.currency}', style: const TextStyle(fontSize: 11, color: C.slate400)),
              ),
            ),
            EntityIcon(iconUrl: wallet.iconUrl, fallback: Icons.account_balance_wallet_outlined, bgColor: const Color(0x1FA855F7), color: kWalletIconFg, size: 52),
            const SizedBox(height: 10),
            const Text('موجودی فعلی', style: TextStyle(fontSize: 12, color: C.slate400)),
            Money('${meta.symbol} ${formatCurrencyAmount(stats.balance, wallet.currency)}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white)),
            Money('≈ ${formatCurrency(bd, mode)}', style: const TextStyle(fontSize: 12, color: C.slate400)),
          ]),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 2.4,
          children: [
            StatPill(label: 'موجودی اولیه', value: '${meta.symbol} ${formatCurrencyAmount(wallet.initialBalance, wallet.currency)}'),
            StatPill(label: 'جریان خالص', value: '${stats.netFlow >= 0 ? '+' : ''}${meta.symbol} ${formatCurrencyAmount(stats.netFlow, wallet.currency)}'),
            StatPill(label: 'جمع درآمد', value: '${meta.symbol} ${formatCurrencyAmount(stats.incomeTotal, wallet.currency)}'),
            StatPill(label: 'جمع هزینه', value: '${meta.symbol} ${formatCurrencyAmount(stats.expenseTotal, wallet.currency)}'),
          ],
        ),
        const SizedBox(height: 12),
        SavingsPotsSection(wallet: wallet, walletBalance: stats.balance),
        const SizedBox(height: 12),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Icon(Icons.credit_card, size: 16, color: C.purple400),
              const SizedBox(width: 6),
              const Expanded(child: Text('اطلاعات حساب', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white))),
              TextButton(onPressed: () => _openPaymentSheet(context, s, wallet), child: Text(hasDetails ? 'ویرایش' : 'افزودن', style: const TextStyle(color: C.purple400, fontSize: 12))),
            ]),
            if (hasDetails) ...[
              if ((wallet.accountOwnerName ?? '').isNotEmpty) CopyRow(label: 'نام صاحب حساب', value: wallet.accountOwnerName!, ltr: false),
              if ((wallet.cardNumber ?? '').isNotEmpty) CopyRow(label: 'شماره کارت', value: formatCardGroups(wallet.cardNumber!), copyValue: wallet.cardNumber),
              if ((wallet.accountNumber ?? '').isNotEmpty) CopyRow(label: 'شماره حساب', value: wallet.accountNumber!),
              if ((wallet.iban ?? '').isNotEmpty) CopyRow(label: 'شبا', value: formatIban(wallet.iban!), copyValue: wallet.iban),
            ] else
              const Text('نام صاحب حساب، شماره کارت، حساب یا شبا را اضافه کنید تا با یک لمس کپی شود.', style: TextStyle(fontSize: 12, color: C.slate500, height: 1.6)),
          ]),
        ),
        const SizedBox(height: 18),
        const Text('تاریخچه تراکنش‌ها', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
        const SizedBox(height: 10),
        if (stats.transactions.isNotEmpty) ...[
          HistorySearchBar(value: query, onChanged: (v) => setState(() => query = v)),
          const SizedBox(height: 8),
          TypeFilterChips(value: typeFilter, onChanged: (v) => setState(() => typeFilter = v)),
          const SizedBox(height: 12),
        ],
        if (stats.transactions.isEmpty)
          EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'هنوز تراکنشی برای این کیف پول ثبت نشده.',
              actionLabel: 'ثبت تراکنش',
              onAction: () => Nav.push(context, '/transactions/new?walletId=${wallet.id}')),
        if (stats.transactions.isNotEmpty && sorted.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(query.trim().isNotEmpty ? 'تراکنشی با این جستجو پیدا نشد.' : 'تراکنشی با این نوع وجود ندارد.', textAlign: TextAlign.center, style: const TextStyle(color: C.slate500, fontSize: 12)),
          ),
        for (final it in sorted)
          if (it.$2 != null)
            ConvertCard(group: it.$2!, assets: s.assets, onEdit: () => Nav.push(context, '/transactions/${it.$2!.sell.id}/edit'), onDelete: () => _deleteConvert(s, it.$2!))
          else
            WalletTxRow(tx: it.$3!, wallet: wallet, store: s, onEdit: () => Nav.push(context, '/transactions/${it.$3!.id}/edit'), onDelete: () => _deleteTx(s, it.$3!.id)),
      ]),
    );
  }

  void _openPaymentSheet(BuildContext context, PortfolioStore s, Wallet wallet) {
    var owner = wallet.accountOwnerName ?? '';
    var card = wallet.cardNumber != null ? formatCardGroups(wallet.cardNumber!) : '';
    var account = wallet.accountNumber ?? '';
    var iban = wallet.iban != null ? formatIban(wallet.iban!) : '';
    var saving = false;
    showAppSheet(context, title: 'اطلاعات حساب', builder: (ctx) {
      return StatefulBuilder(builder: (ctx, setSt) {
        Future<void> save() async {
          final cardN = card.replaceAll(RegExp(r'\D'), '');
          final accN = account.replaceAll(RegExp(r'\D'), '');
          var ib = iban.replaceAll(RegExp(r'\s'), '').toUpperCase();
          if (ib.isNotEmpty && !ib.startsWith('IR')) ib = 'IR${ib.replaceFirst(RegExp(r'^IR', caseSensitive: false), '')}';
          final name = owner.replaceAll(RegExp(r'\s+'), ' ').trim();
          final normalized = {
            'card_number': cardN.isEmpty ? null : cardN,
            'account_number': accN.isEmpty ? null : accN,
            'iban': ib.isEmpty ? null : ib,
            'account_owner_name': name.isEmpty ? null : name,
          };
          setSt(() => saving = true);
          try {
            final data = await Supabase.instance.client.from('wallets').update(normalized).eq('id', wallet.id).select().single();
            final saved = Wallet.fromJson(data);
            s.update((st) => st.wallets = st.wallets.map((w) => w.id == saved.id ? saved : w).toList());
            Toast.success('اطلاعات حساب ذخیره شد.');
            if (ctx.mounted) Navigator.pop(ctx);
          } catch (_) {
            Toast.error('خطا در ذخیره.');
            setSt(() => saving = false);
          }
        }

        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('همه فیلدها اختیاری‌اند. برای کارت و حساب فقط رقم وارد کنید.', style: TextStyle(fontSize: 12, color: C.slate400)),
          const SizedBox(height: 14),
          Field(label: 'نام صاحب حساب', child: AppTextField(value: owner, onChanged: (v) => owner = v, hint: 'مثلاً علی رضایی')),
          Field(
            label: 'شماره کارت',
            child: AppTextField(
              value: card,
              ltr: true,
              keyboardType: TextInputType.number,
              hint: '۶۰۳۷ ۹۹۱۲ ۳۴۵۶ ۷۸۹۰',
              onChanged: (v) => setSt(() => card = formatCardGroups(latinizeDigits(v))),
              formatters: [LengthLimitingTextInputFormatter(19)],
            ),
          ),
          Field(
            label: 'شماره حساب',
            child: AppTextField(value: account, ltr: true, keyboardType: TextInputType.number, hint: '۱۰ رقمی یا بیشتر', onChanged: (v) => setSt(() => account = latinizeDigits(v).replaceAll(RegExp(r'\D'), ''))),
          ),
          Field(
            label: 'شبا (IBAN)',
            child: AppTextField(
              value: iban,
              ltr: true,
              hint: 'IR12 3456 7890 1234 5678 9012 34',
              onChanged: (v) => setSt(() => iban = formatIban(latinizeDigits(v))),
              formatters: [LengthLimitingTextInputFormatter(32)],
            ),
          ),
          AppButton(saving ? 'در حال ذخیره...' : 'ذخیره', expand: true, loading: saving, onPressed: save),
        ]);
      });
    });
  }
}

class CopyRow extends StatefulWidget {
  final String label, value;
  final String? copyValue;
  final bool ltr;
  const CopyRow({super.key, required this.label, required this.value, this.copyValue, this.ltr = true});
  @override
  State<CopyRow> createState() => _CopyRowState();
}

class _CopyRowState extends State<CopyRow> {
  bool copied = false;
  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          try {
            await Clipboard.setData(ClipboardData(text: widget.copyValue ?? widget.value));
            setState(() => copied = true);
            Toast.success('کپی شد.');
            Future.delayed(const Duration(milliseconds: 1500), () {
              if (mounted) setState(() => copied = false);
            });
          } catch (_) {
            Toast.error('کپی ناموفق بود.');
          }
        },
        child: Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: C.white5, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.label, style: const TextStyle(fontSize: 11, color: C.slate500)),
                Text(widget.value, textDirection: widget.ltr ? TextDirection.ltr : null, style: const TextStyle(fontSize: 14, color: C.slate200, letterSpacing: 0.5)),
              ]),
            ),
            Icon(copied ? Icons.check : Icons.copy, size: 16, color: copied ? C.emerald400 : C.slate400),
          ]),
        ),
      );
}

class WalletTxRow extends StatelessWidget {
  final Transaction tx;
  final Wallet wallet;
  final PortfolioStore store;
  final VoidCallback onEdit, onDelete;
  const WalletTxRow({super.key, required this.tx, required this.wallet, required this.store, required this.onEdit, required this.onDelete});

  String _counterparty() {
    final isSource = tx.sourceWalletId == wallet.id;
    final ow = isSource ? tx.targetWalletId : tx.sourceWalletId;
    final oa = isSource ? tx.targetAssetId : tx.sourceAssetId;
    if (ow != null) {
      final w = findWallet(store.wallets, ow);
      return w != null ? '→ ${w.name}' : '— کیف پول حذف‌شده';
    }
    if (oa != null) {
      final a = findAsset(store.assets, oa);
      return a != null ? '→ ${a.name}' : '— دارایی حذف‌شده';
    }
    if ((tx.type == 'INCOME' || tx.type == 'EXPENSE') && tx.categoryId != null) {
      final c = store.categories.where((x) => x.id == tx.categoryId).firstOrNull;
      if (c != null) return c.name;
    }
    if (tx.type == 'INCOME') return 'درآمد بدون دسته';
    if (tx.type == 'EXPENSE') return 'هزینه بدون دسته';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final isSource = tx.sourceWalletId == wallet.id;
    final amount = isSource ? jsNum(tx.sourceAmount) : jsNum(tx.targetAmount);
    final isIn = !isSource;
    final tone = isIn ? C.emerald400 : C.rose400;
    final icon = tx.type == 'TRANSFER' ? Icons.swap_horiz : (isIn ? Icons.south_east : Icons.north_east);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(color: C.raised, border: Border(left: BorderSide(color: isIn ? C.emerald : C.rose, width: 4))),
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            Row(children: [
              Container(width: 36, height: 36, decoration: BoxDecoration(color: C.white5, borderRadius: BorderRadius.circular(12)), child: Icon(icon, size: 16, color: tone)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(kTxTypeLabels[tx.type] ?? tx.type, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.slate200)),
                  Text(_counterparty(), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: C.slate500)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Money('${isIn ? '+' : '-'}${currencyMeta(wallet.currency).symbol} ${formatCurrencyAmount(amount.abs(), wallet.currency)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: tone)),
                Text(latinizeDigits(tx.dateString), style: const TextStyle(fontSize: 11, color: C.slate500)),
              ]),
            ]),
            Row(children: [
              Expanded(child: Text(tx.note ?? '', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: C.slate500))),
              IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.edit_outlined, size: 17, color: C.slate400), onPressed: onEdit),
              IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.delete_outline, size: 17, color: C.rose300), onPressed: onDelete),
            ]),
          ]),
        ),
      ),
    );
  }
}

class SavingsPotsSection extends StatefulWidget {
  final Wallet wallet;
  final double walletBalance;
  const SavingsPotsSection({super.key, required this.wallet, required this.walletBalance});
  @override
  State<SavingsPotsSection> createState() => _SavingsPotsSectionState();
}

class _SavingsPotsSectionState extends State<SavingsPotsSection> {
  List<WalletSavingsPot> pots = [];
  bool loading = true, submitting = false, formOpen = false;
  String? editingId;
  String name = '', color = kCategoryColors[0], targetAmount = '', currentAmount = '0';

  SupabaseClient get _c => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => loading = true);
    try {
      final data = await _c
          .from('wallet_savings_pots')
          .select()
          .eq('wallet_id', widget.wallet.id)
          .isFilter('archived_at', null)
          .order('order_index', ascending: true)
          .order('created_at', ascending: true);
      pots = (data as List).cast<Json>().map(WalletSavingsPot.fromJson).toList();
    } catch (_) {
      Toast.error('خطا در دریافت قلک‌ها.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  double get allocated => pots.fold(0.0, (s, p) => s + p.currentAmount);
  double get free => math.max(widget.walletBalance - allocated, 0);

  bool _canSet(String potId, double next) {
    if (!next.isFinite || next < 0) return false;
    final other = pots.where((p) => p.id != potId).fold(0.0, (s, p) => s + p.currentAmount);
    return other + next <= widget.walletBalance + 1e-6;
  }

  void _reset() => setState(() {
        editingId = null;
        name = '';
        color = kCategoryColors[0];
        targetAmount = '';
        currentAmount = '0';
        formOpen = false;
      });

  Future<void> _submit() async {
    final user = context.read<PortfolioStore>().user;
    if (user == null) return;
    final nm = name.trim();
    if (nm.isEmpty) {
      Toast.error('نام قلک الزامی است.');
      return;
    }
    final cur = canonicalToNumber(currentAmount.isEmpty ? '0' : currentAmount);
    final tgt = targetAmount.trim().isNotEmpty ? canonicalToNumber(targetAmount) : null;
    if (!cur.isFinite || cur < 0) {
      Toast.error('مبلغ تخصیص‌یافته نامعتبر است.');
      return;
    }
    if (tgt != null && (!tgt.isFinite || tgt <= 0)) {
      Toast.error('هدف پس‌انداز نامعتبر است.');
      return;
    }
    if (!_canSet(editingId ?? '__new__', cur)) {
      Toast.error('جمع تخصیص قلک‌ها از موجودی کیف پول بیشتر است.');
      return;
    }
    setState(() => submitting = true);
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      if (editingId != null) {
        await _c.from('wallet_savings_pots').update({'name': nm, 'color': color, 'target_amount': tgt, 'current_amount': cur, 'updated_at': now}).eq('id', editingId!);
        Toast.success('قلک ویرایش شد.');
      } else {
        final nextOrder = pots.fold(-1, (m, p) => math.max(m, p.orderIndex)) + 1;
        await _c.from('wallet_savings_pots').insert({
          'user_id': user.id,
          'wallet_id': widget.wallet.id,
          'name': nm,
          'color': color,
          'target_amount': tgt,
          'current_amount': cur,
          'order_index': nextOrder,
        });
        Toast.success('قلک اضافه شد.');
      }
      _reset();
      await _refresh();
    } catch (_) {
      Toast.error('خطا در ذخیره قلک.');
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<void> _archive(WalletSavingsPot p) async {
    if (!await confirmDialog(context, message: 'قلک «${p.name}» حذف شود؟', danger: true, confirmLabel: 'حذف')) return;
    setState(() => submitting = true);
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      await _c.from('wallet_savings_pots').update({'archived_at': now, 'updated_at': now}).eq('id', p.id);
      Toast.success('قلک حذف شد.');
      if (editingId == p.id) _reset();
      await _refresh();
    } catch (_) {
      Toast.error('خطا در حذف قلک.');
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<void> _nudge(WalletSavingsPot p, double delta) async {
    final next = p.currentAmount + delta;
    if (!_canSet(p.id, next)) {
      Toast.error('موجودی آزاد کافی نیست.');
      return;
    }
    setState(() => submitting = true);
    try {
      await _c.from('wallet_savings_pots').update({'current_amount': next, 'updated_at': DateTime.now().toUtc().toIso8601String()}).eq('id', p.id);
      await _refresh();
    } catch (_) {
      Toast.error('خطا در به‌روزرسانی تخصیص.');
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cur = widget.wallet.currency;
    final sym = currencyMeta(cur).symbol;
    final wb = widget.walletBalance;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.savings_outlined, size: 16, color: C.purple400),
          const SizedBox(width: 6),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('قلک‌ها', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
              Text('تخصیص مجازی داخل این کیف — تراکنش جدا ثبت نمی‌شود', style: TextStyle(fontSize: 10, color: C.slate500)),
            ]),
          ),
          if (!formOpen) AppButton('جدید', icon: Icons.add, dense: true, variant: BtnVariant.secondary, onPressed: () => setState(() => formOpen = true)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: StatPill(label: 'تخصیص‌شده', value: '$sym ${formatCurrencyAmount(allocated, cur)}')),
          const SizedBox(width: 8),
          Expanded(child: StatPill(label: 'آزاد', value: '$sym ${formatCurrencyAmount(free, cur)}')),
        ]),
        if (allocated > wb + 1e-6)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('جمع قلک‌ها از موجودی فعلی کیف پول بیشتر است. یکی از قلک‌ها را کم کن.', style: TextStyle(fontSize: 11, color: C.amber300)),
          ),
        if (formOpen)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: C.white5, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(editingId != null ? 'ویرایش قلک' : 'قلک جدید', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.slate200))),
                IconButton(icon: const Icon(Icons.close, size: 16, color: C.slate400), onPressed: _reset),
              ]),
              AppTextField(value: name, onChanged: (v) => name = v, hint: 'نام (مثلا: سفر، اضطراری)', formatters: [LengthLimitingTextInputFormatter(64)]),
              const SizedBox(height: 10),
              ColorRow(value: color, onChanged: (c) => setState(() => color = c)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: Field(label: 'تخصیص فعلی', child: NumberInput(value: currentAmount, onChanged: (v) => currentAmount = v))),
                const SizedBox(width: 8),
                Expanded(child: Field(label: 'هدف (اختیاری)', child: NumberInput(value: targetAmount, onChanged: (v) => targetAmount = v, hint: '—'))),
              ]),
              AppButton(submitting ? 'در حال ذخیره...' : (editingId != null ? 'ذخیره' : 'افزودن قلک'), expand: true, onPressed: submitting ? null : _submit),
            ]),
          ),
        const SizedBox(height: 10),
        if (loading)
          const Text('در حال دریافت...', style: TextStyle(fontSize: 12, color: C.slate500))
        else if (pots.isEmpty)
          const Text('هنوز قلکی نساخته‌ای. برای بودجه‌بندی مجازی داخل همین کیف، یک قلک بساز.', style: TextStyle(fontSize: 12, color: C.slate500, height: 1.6))
        else
          for (final p in pots)
            Builder(builder: (_) {
              final t = p.targetAmount ?? 0;
              final prog = t > 0 ? math.min(p.currentAmount / t * 100, 999.0) : null;
              final width = prog != null ? prog.clamp(0, 100).toDouble() : 0.0;
              final step = math.max(wb * 0.05, 1.0);
              return Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: C.white5, borderRadius: BorderRadius.circular(14)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Dot(hexColor(p.color)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.name, style: const TextStyle(fontSize: 13, color: C.slate200)),
                        Money('$sym ${formatCurrencyAmount(p.currentAmount, cur)}${p.targetAmount != null ? ' / ${formatCurrencyAmount(p.targetAmount, cur)}' : ''}',
                            style: const TextStyle(fontSize: 11, color: C.slate400)),
                      ]),
                    ),
                    TextButton(
                      onPressed: submitting
                          ? null
                          : () => setState(() {
                                editingId = p.id;
                                name = p.name;
                                color = p.color;
                                targetAmount = p.targetAmount != null ? jsNumStr(p.targetAmount) : '';
                                currentAmount = jsNumStr(p.currentAmount);
                                formOpen = true;
                              }),
                      child: const Text('ویرایش', style: TextStyle(fontSize: 11, color: C.slate300)),
                    ),
                    IconButton(icon: const Icon(Icons.delete_outline, size: 15, color: C.rose300), onPressed: submitting ? null : () => _archive(p)),
                  ]),
                  if (prog != null) ...[
                    Row(children: [
                      const Expanded(child: Text('پیشرفت هدف', style: TextStyle(fontSize: 10, color: C.slate500))),
                      Text('${toPersianDigits(prog.round())}٪', style: const TextStyle(fontSize: 10, color: C.slate400)),
                    ]),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(value: (width > 0 ? math.max(width, 4) : 0) / 100, minHeight: 5, backgroundColor: C.white5, color: hexColor(p.color)),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: AppButton('−۵٪', dense: true, variant: BtnVariant.secondary, expand: true, onPressed: submitting ? null : () => _nudge(p, -step))),
                    const SizedBox(width: 8),
                    Expanded(child: AppButton('+۵٪', dense: true, variant: BtnVariant.secondary, expand: true, onPressed: submitting || free <= 0 ? null : () => _nudge(p, math.min(free, step)))),
                  ]),
                ]),
              );
            }),
      ]),
    );
  }
}

class ColorRow extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const ColorRow({super.key, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final c in kCategoryColors)
          GestureDetector(
            onTap: () {
              haptic();
              onChanged(c);
            },
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: hexColor(c), shape: BoxShape.circle, border: Border.all(color: value == c ? Colors.white : Colors.transparent, width: 2)),
              child: value == c ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
            ),
          ),
      ]);
}
