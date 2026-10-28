// Port of AddTransactionView.tsx + TransactionFormRow.tsx + ConvertTransactionForm.tsx.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/logic/ledger.dart';
import '../../core/models.dart';
import '../../core/services/api.dart';
import '../../core/services/prices.dart';
import '../../core/store.dart';
import '../../core/ui/category_picker.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/toast.dart';
import '../../core/ui/widgets.dart';
import '../../core/utils/format.dart';
import '../../core/utils/jalali.dart';
import 'endpoint_picker.dart';
import 'tx_logic.dart';

class AddTransactionScreen extends StatefulWidget {
  final String? assetId, walletId, targetAssetId, sourceAmount, targetAmount, personId, personSide, settleAmount, defaultType, defaultUiMode, transactionId;
  const AddTransactionScreen({
    super.key,
    this.assetId,
    this.walletId,
    this.targetAssetId,
    this.sourceAmount,
    this.targetAmount,
    this.personId,
    this.personSide,
    this.settleAmount,
    this.defaultType,
    this.defaultUiMode,
    this.transactionId,
  });

  factory AddTransactionScreen.fromQuery(Map<String, String> q, {String? transactionId}) {
    const valid = {'BUY', 'SELL', 'TRANSFER', 'INCOME', 'EXPENSE'};
    final type = q['type'];
    return AddTransactionScreen(
      assetId: q['assetId'],
      walletId: q['walletId'],
      targetAssetId: q['targetAssetId'],
      sourceAmount: q['sourceAmount'],
      targetAmount: q['targetAmount'],
      personId: q['personId'],
      personSide: q['personSide'] == 'source' || q['personSide'] == 'target' ? q['personSide'] : null,
      settleAmount: q['amount'],
      defaultType: type != null && valid.contains(type) ? type : null,
      defaultUiMode: type == kConvertMode ? kConvertMode : null,
      transactionId: transactionId,
    );
  }

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  late String uiMode;
  late List<TxForm> rows;
  late ConvertForm convertForm;
  final Map<int, bool> collapsed = {};
  bool submitting = false;
  String? formError;
  Transaction? txToEdit;
  ConvertPair? convertPair;
  bool notFound = false;

  PortfolioStore get store => context.read<PortfolioStore>();

  FormDefaults _defaults([String? type]) => FormDefaults(
        assetId: widget.assetId,
        walletId: widget.walletId,
        defaultType: type ?? widget.defaultType,
        personId: widget.personId,
        personSide: widget.personSide,
        settleAmount: widget.settleAmount,
      );

  @override
  void initState() {
    super.initState();
    final s = context.read<PortfolioStore>();
    if (widget.transactionId != null) {
      for (final t in s.transactions) {
        if (t.id == widget.transactionId) txToEdit = t;
      }
      if (txToEdit == null) notFound = true;
    }
    convertPair = txToEdit != null ? resolveConvertPair(txToEdit!, s.transactions) : null;
    uiMode = widget.defaultUiMode ?? (convertPair != null ? kConvertMode : (txToEdit?.type ?? widget.defaultType ?? 'BUY'));
    rows = [buildInitialForm(txToEdit, _defaults(), s.usdRate)];
    convertForm = buildInitialConvertForm(
      s.assets,
      s.usdRate,
      assetId: widget.assetId,
      targetAssetId: widget.targetAssetId,
      sourceAmount: widget.sourceAmount,
      targetAmount: widget.targetAmount,
      pair: convertPair,
    );
  }

  bool get isEdit => txToEdit != null;
  bool get isConvertMode => uiMode == kConvertMode;
  bool get isConvertEdit => isEdit && convertPair != null;

  void switchUiMode(String mode) {
    if (isEdit || mode == uiMode) return;
    setState(() {
      uiMode = mode;
      if (mode == kConvertMode) {
        convertForm = buildInitialConvertForm(store.assets, store.usdRate,
            assetId: widget.assetId, targetAssetId: widget.targetAssetId, sourceAmount: widget.sourceAmount, targetAmount: widget.targetAmount);
      } else {
        rows = [buildInitialForm(null, _defaults(mode), store.usdRate)];
      }
    });
  }

  void addRow() {
    setState(() {
      final base = buildInitialForm(null, FormDefaults(defaultType: rows.first.type), store.usdRate);
      final last = rows.last;
      base.date = last.date;
      base.sourceKind = last.sourceKind;
      base.sourceId = last.sourceId;
      rows = [...rows, base];
    });
  }

  void removeRow(int idx) {
    if (rows.length <= 1) return;
    setState(() {
      rows = [...rows]..removeAt(idx);
      collapsed.remove(idx);
    });
  }

  Future<void> _persistTradeSnapshots(List<Transaction> txs) async {
    final s = store;
    final candidates = buildTradeSnapshots(txs, s.user!.id);
    if (candidates.isEmpty) return;
    final manual = s.dailyPrices.where((p) => p.source == 'manual').map((p) => '${p.assetId}|${p.dateString}').toSet();
    final byKey = <String, Json>{};
    for (final r in candidates) {
      final k = '${r['asset_id']}|${r['date_string']}';
      if (manual.contains(k)) continue;
      byKey[k] = r;
    }
    if (byKey.isEmpty) return;
    try {
      final data = await Supabase.instance.client.from('daily_prices').upsert(byKey.values.toList(), onConflict: 'user_id,asset_id,date_string').select();
      final fresh = (data as List).cast<Json>().map(DailyPrice.fromJson).toList();
      if (fresh.isEmpty) return;
      s.update((st) => st.dailyPrices = mergeDailyPrices(st.dailyPrices, fresh));
    } catch (_) {}
  }

  void _undoInsert(List<String> ids, String doneMsg) async {
    try {
      await Supabase.instance.client.from('transactions').delete().inFilter('id', ids);
      store.update((st) => st.transactions = st.transactions.where((t) => !ids.contains(t.id)).toList());
      Toast.info(doneMsg);
    } catch (_) {
      Toast.error('لغو ثبت ناموفق بود.');
    }
  }

  Future<void> submit() async {
    setState(() => formError = null);
    final s = store;
    final user = s.user;
    if (user == null) return;
    final client = Supabase.instance.client;
    if (isConvertMode) {
      final err = validateConvertForm(convertForm, s.transactions, s.wallets);
      if (err != null) {
        setState(() => formError = err);
        Toast.error(err);
        return;
      }
      setState(() => submitting = true);
      try {
        final eff = applyMatchBuyValue(convertForm);
        final opId = eff.operationId ?? const Uuid().v4();
        final (sellP, buyP) = buildConvertPayloads(eff, user.id, s.wallets, s.currencyRates, s.usdRate, opId);
        if (isConvertEdit && eff.sellTransactionId != null && eff.buyTransactionId != null) {
          final res = await Future.wait([
            client.from('transactions').update(sellP).eq('id', eff.sellTransactionId!).select().single(),
            client.from('transactions').update(buyP).eq('id', eff.buyTransactionId!).select().single(),
          ]);
          final updated = res.map(Transaction.fromJson).toList();
          s.update((st) => st.transactions = st.transactions.map((t) => updated.firstWhere((u) => u.id == t.id, orElse: () => t)).toList());
          await _persistTradeSnapshots(updated);
          Toast.success('تبدیل به‌روزرسانی شد.');
        } else {
          final data = await client.from('transactions').insert([sellP, buyP]).select();
          final inserted = (data as List).cast<Json>().map(Transaction.fromJson).toList();
          s.update((st) => st.transactions = [...inserted.reversed, ...st.transactions]);
          await _persistTradeSnapshots(inserted);
          final ids = inserted.map((t) => t.id).toList();
          Toast.success('تبدیل ثبت شد.', durationMs: 8000, actionLabel: 'لغو', onAction: () => _undoInsert(ids, 'ثبت تبدیل لغو شد.'));
        }
        if (mounted) Navigator.pop(context);
      } catch (e) {
        Toast.error('خطا در ثبت تبدیل.');
      } finally {
        if (mounted) setState(() => submitting = false);
      }
      return;
    }

    final balanceTxs = txToEdit != null ? s.transactions.where((t) => t.id != txToEdit!.id).toList() : s.transactions;
    final reserved = <String, double>{};
    for (var i = 0; i < rows.length; i++) {
      final key = sourceEndpointKey(rows[i]);
      final r = key != null ? (reserved[key] ?? 0) : 0.0;
      final err = validateForm(rows[i], s.wallets) ?? validateSourceFunds(rows[i], s.wallets, balanceTxs, s.persons, r);
      if (key != null && err == null) {
        final a = n(rows[i].sourceAmount);
        if (a.isFinite && a > 0) reserved[key] = r + a;
      }
      if (err != null) {
        final msg = rows.length > 1 ? 'تراکنش #${i + 1}: $err' : err;
        setState(() {
          formError = msg;
          collapsed[i] = false;
        });
        Toast.error(msg);
        return;
      }
    }
    setState(() => submitting = true);
    try {
      if (txToEdit != null) {
        final payload = buildPayload(rows.first, user.id, s.wallets, s.currencyRates, s.usdRate);
        final data = await client.from('transactions').update(payload).eq('id', txToEdit!.id).select().single();
        final updated = Transaction.fromJson(data);
        s.update((st) => st.transactions = st.transactions.map((t) => t.id == updated.id ? updated : t).toList());
        await _persistTradeSnapshots([updated]);
        Toast.success('تراکنش به‌روزرسانی شد.');
      } else {
        final payloads = rows.map((r) => buildPayload(r, user.id, s.wallets, s.currencyRates, s.usdRate)).toList();
        final data = await client.from('transactions').insert(payloads).select();
        final inserted = (data as List).cast<Json>().map(Transaction.fromJson).toList();
        s.update((st) => st.transactions = [...inserted.reversed, ...st.transactions]);
        await _persistTradeSnapshots(inserted);
        Api.fireExpenseAlert(inserted.where((t) => t.type == 'EXPENSE').map((t) => t.id).toList());
        final ids = inserted.map((t) => t.id).toList();
        Toast.success(inserted.length > 1 ? '${inserted.length} تراکنش ثبت شد.' : 'تراکنش ثبت شد.',
            durationMs: 8000, actionLabel: 'لغو', onAction: () => _undoInsert(ids, 'ثبت تراکنش لغو شد.'));
      }
      haptic('success');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      Toast.error('خطا در ثبت تراکنش.');
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<PortfolioStore>();
    if (notFound) {
      return const SubPage(title: 'تراکنش', body: Center(child: Text('تراکنش پیدا نشد.', style: TextStyle(color: C.slate400))));
    }
    final style = kTypeStyles[uiMode]!;
    final title = isEdit
        ? (isConvertEdit ? 'ویرایش تبدیل' : 'ویرایش تراکنش')
        : (isConvertMode ? 'تبدیل دارایی' : (rows.length > 1 ? 'ثبت ${rows.length} تراکنش' : 'ثبت تراکنش جدید'));
    final submitLabel = submitting
        ? 'در حال ارسال...'
        : isEdit
            ? (isConvertEdit ? 'ثبت تغییرات تبدیل' : 'ثبت تغییرات')
            : (isConvertMode ? 'ثبت تبدیل' : (rows.length > 1 ? 'ثبت ${rows.length} تراکنش' : 'ثبت تراکنش'));
    final balanceTxs = txToEdit != null ? s.transactions.where((t) => t.id != txToEdit!.id).toList() : s.transactions;
    return SubPage(
      title: title,
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
        if (formError != null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: C.rose.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.rose.withValues(alpha: 0.3))),
            child: Text(formError!, style: const TextStyle(color: C.rose400, fontSize: 12)),
          ),
        _TypeTabs(value: uiMode, locked: isEdit, onChanged: switchUiMode),
        if (isEdit)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(isConvertEdit ? 'تبدیل پس از ثبت به‌صورت فروش + خرید ویرایش می‌شود.' : 'نوع تراکنش پس از ثبت قابل تغییر نیست.',
                style: const TextStyle(fontSize: 11, color: C.slate500)),
          ),
        const SizedBox(height: 14),
        if (isConvertMode)
          _ConvertFormView(form: convertForm, onChange: (f) => setState(() => convertForm = f), store: s)
        else ...[
          for (var i = 0; i < rows.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _FormRow(
                key: ValueKey('row$i-${rows.length}'),
                form: rows[i],
                rowIndex: i,
                totalRows: rows.length,
                isCollapsed: collapsed[i] ?? false,
                canRemove: !isEdit && rows.length > 1,
                onChange: (f) => setState(() => rows = [...rows]..[i] = f),
                onRemove: () => removeRow(i),
                onToggle: () => setState(() => collapsed[i] = !(collapsed[i] ?? false)),
                store: s,
                transactions: balanceTxs,
              ),
            ),
          if (!isEdit)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AppButton('افزودن تراکنش دیگر', icon: Icons.add, variant: BtnVariant.secondary, expand: true, onPressed: addRow),
            ),
          _PreviewPanel(rows: rows, store: s, style: style),
        ],
        const SizedBox(height: 16),
        Material(
          color: style.accent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: submitting ? null : submit,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(submitLabel, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ),
      ]),
    );
  }
}

class _TypeTabs extends StatelessWidget {
  final String value;
  final bool locked;
  final ValueChanged<String> onChanged;
  const _TypeTabs({required this.value, required this.locked, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    Widget tab(String t) {
      final s = kTypeStyles[t]!;
      final active = value == t;
      return Expanded(
        child: Opacity(
          opacity: locked && !active ? 0.3 : 1,
          child: GestureDetector(
            onTap: locked && !active
                ? null
                : () {
                    haptic();
                    onChanged(t);
                  },
            child: Container(
              margin: const EdgeInsets.all(3),
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(color: active ? s.accent : Colors.transparent, borderRadius: BorderRadius.circular(9)),
              child: Text(s.label, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: active ? Colors.white : C.slate400)),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: C.raised, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.white10)),
      child: Column(children: [
        Row(children: [for (final t in kUiTabs.sublist(0, 3)) tab(t)]),
        Row(children: [for (final t in kUiTabs.sublist(3)) tab(t)]),
      ]),
    );
  }
}

BoxDecoration _accentBox(Color accent) => BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: accent.withValues(alpha: 0.3)),
      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [accent.withValues(alpha: 0.15), Colors.transparent]),
    );

class _FormRow extends StatefulWidget {
  final TxForm form;
  final int rowIndex, totalRows;
  final bool isCollapsed, canRemove;
  final ValueChanged<TxForm> onChange;
  final VoidCallback onRemove, onToggle;
  final PortfolioStore store;
  final List<Transaction> transactions;
  const _FormRow({
    super.key,
    required this.form,
    required this.rowIndex,
    required this.totalRows,
    required this.isCollapsed,
    required this.canRemove,
    required this.onChange,
    required this.onRemove,
    required this.onToggle,
    required this.store,
    required this.transactions,
  });
  @override
  State<_FormRow> createState() => _FormRowState();
}

class _FormRowState extends State<_FormRow> {
  PortfolioStore get s => widget.store;
  TxForm get form => widget.form;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _seedPrices());
  }

  @override
  void didUpdateWidget(covariant _FormRow old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) => _seedPrices());
  }

  /// The two `useEffect` seeds from TransactionFormRow.tsx.
  void _seedPrices() {
    if (!mounted) return;
    final f = form;
    final current = n(f.priceToman);
    if (current.isFinite && current > 0) return;
    if (f.type == 'INCOME' || f.type == 'EXPENSE') {
      final w = f.type == 'INCOME' ? (f.targetKind == 'wallet' ? findWallet(s.wallets, f.targetId) : null) : (f.sourceKind == 'wallet' ? findWallet(s.wallets, f.sourceId) : null);
      if (w == null || w.currency == 'IRT') return;
      final rate = walletRateForTransfer(w, s.currencyRates, s.usdRate, f.usdRate);
      if (!(rate > 0)) return;
      widget.onChange(f.copy()..priceToman = canonicalNumber(rate));
      return;
    }
    if (f.type == 'TRANSFER') {
      final a = f.sourceKind == 'wallet' && f.targetKind == 'asset'
          ? findAsset(s.assets, f.targetId)
          : (f.sourceKind == 'asset' && f.targetKind == 'wallet' ? findAsset(s.assets, f.sourceId) : null);
      if (a == null || !(a.priceToman > 0)) return;
      final next = f.copy()..priceToman = canonicalNumber(a.priceToman);
      widget.onChange(recomputeTransferTarget(next, s.wallets, s.assets, s.currencyRates, s.usdRate));
    }
  }

  TxForm _recompute(TxForm next) {
    if (next.type == 'BUY' || next.type == 'SELL') return recomputeMoneySide(next, s.wallets, s.currencyRates, s.usdRate);
    if (next.type == 'TRANSFER') return recomputeTransferTarget(next, s.wallets, s.assets, s.currencyRates, s.usdRate);
    return next;
  }

  void _setDate(String v) {
    final prev = form;
    final next = prev.copy()..date = v;
    next.usdRate = usdRateAfterDateChange(prev, v, (d) => usdRateOn(s.rateHistories, d, todayStr(), s.usdRate));
    widget.onChange(next.usdRate != prev.usdRate ? _recompute(next) : next);
  }

  void _setPrice(String v) => widget.onChange(_recompute(form.copy()..priceToman = v));
  void _setUsd(String v) => widget.onChange(_recompute(form.copy()..usdRate = v));

  void _setPrimary(String v) {
    final next = form.copy();
    if (kPrimarySide[form.type] == 'source') {
      next.sourceAmount = v;
    } else {
      next.targetAmount = v;
    }
    widget.onChange(_recompute(next));
  }

  Future<void> _pickEndpoint(String side) async {
    final shape = kTypeShapes[form.type]!;
    final r = await showEndpointPicker(
      context,
      title: side == 'source' ? 'انتخاب مبدأ' : 'انتخاب مقصد',
      allow: (side == 'source' ? shape.source : shape.target) ?? const [],
      excludeIds: form.sourceKind == form.targetKind ? [(side == 'source' ? form.targetId : form.sourceId) ?? ''] : const [],
      wallets: s.wallets,
      assets: s.assets,
      persons: s.persons,
      transactions: widget.transactions,
    );
    if (r == null) return;
    final next = form.copy();
    if (side == 'source') {
      next.sourceKind = r.$1;
      next.sourceId = r.$2;
    } else {
      next.targetKind = r.$1;
      next.targetId = r.$2;
    }
    widget.onChange(_recompute(next));
  }

  @override
  Widget build(BuildContext context) {
    final f = form;
    final shape = kTypeShapes[f.type]!;
    final style = kTypeStyles[f.type]!;
    final pricing = pricingContextOf(f, s.wallets);
    final isBulk = widget.totalRows > 1;
    final sw = f.sourceKind == 'wallet' ? findWallet(s.wallets, f.sourceId) : null;
    final sa = f.sourceKind == 'asset' ? findAsset(s.assets, f.sourceId) : null;
    final tw = f.targetKind == 'wallet' ? findWallet(s.wallets, f.targetId) : null;
    final ta = f.targetKind == 'asset' ? findAsset(s.assets, f.targetId) : null;
    Person? personOf(String? id) {
      for (final p in s.persons) {
        if (p.id == id) return p;
      }
      return null;
    }

    final srcBal = sourceBalance(f, s.wallets, widget.transactions, s.persons);
    final srcNum = n(f.sourceAmount);
    final insufficient = f.type != 'INCOME' && f.sourceKind != 'person' && srcBal != null && srcNum.isFinite && srcNum > srcBal;
    final primary = kPrimarySide[f.type]!;

    if (isBulk && widget.isCollapsed) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: _accentBox(style.accent),
        child: Row(children: [
          Text('#${widget.rowIndex + 1}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: style.accent)),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              onTap: widget.onToggle,
              child: Text(summarizeForm(f, s.wallets, s.assets, s.categories, s.persons), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: C.slate200)),
            ),
          ),
          if (widget.canRemove) IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: C.rose300), onPressed: widget.onRemove),
        ]),
      );
    }

    final jd = parseJalaali(f.date);
    final today = todayJalaali();
    final yesterday = addDays(today, -1);
    final canQuick = primary == 'source' && f.sourceKind != null && f.sourceId != null && srcBal != null && srcBal > 0;

    double? targetBal;
    if (f.targetKind == 'wallet' && tw != null) {
      targetBal = calculateWalletStats(tw, widget.transactions).balance;
    } else if (f.targetKind == 'person' && f.targetId != null) {
      targetBal = sourceBalance(f.copy()
        ..sourceKind = 'person'
        ..sourceId = f.targetId, s.wallets, widget.transactions, s.persons);
    }

    final primaryWallet = primary == 'source' ? sw : tw;
    final primaryAsset = primary == 'source' ? sa : ta;
    final unit = primaryWallet != null ? currencyMeta(primaryWallet.currency).label : (primaryAsset?.unit ?? '');
    final u = unit.isNotEmpty ? ' ($unit)' : '';
    final primaryLabel = switch (f.type) {
      'BUY' => 'مقدار خرید$u',
      'SELL' => 'مقدار فروش$u',
      'INCOME' => 'مبلغ درآمد$u',
      'EXPENSE' => 'مبلغ هزینه$u',
      _ => 'مقدار$u',
    };

    final showDerived = (f.type == 'BUY' && sw != null) ||
        (f.type == 'SELL' && tw != null) ||
        (f.type == 'TRANSFER' && ((sw != null && ta != null) || (sa != null && tw != null)));
    final showCross = f.type == 'TRANSFER' && !((sw != null && tw != null && sw.currency == tw.currency) || (sw != null && ta != null) || (sa != null && tw != null));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _accentBox(style.accent),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (isBulk)
          Row(children: [
            Text('تراکنش #${widget.rowIndex + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: style.accent)),
            const Spacer(),
            IconButton(icon: const Icon(Icons.expand_less, size: 18, color: C.slate400), onPressed: widget.onToggle),
            if (widget.canRemove) IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: C.rose300), onPressed: widget.onRemove),
          ]),
        if (shape.source != null)
          _DirectionCard(
            label: 'مبدأ',
            kind: f.sourceKind,
            wallet: sw,
            asset: sa,
            person: f.sourceKind == 'person' ? personOf(f.sourceId) : null,
            balance: srcBal,
            insufficient: insufficient,
            optional: f.type == 'BUY',
            onTap: () => _pickEndpoint('source'),
          ),
        if (f.type == 'BUY' && (f.sourceKind != null || f.sourceId != null))
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: () => widget.onChange(f.copy()
                ..sourceKind = null
                ..sourceId = null
                ..sourceAmount = ''),
              child: const Text('بدون ثبت مبدأ', style: TextStyle(fontSize: 11, color: C.slate400)),
            ),
          ),
        if (shape.source != null && shape.target != null)
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 6),
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(color: C.white5, shape: BoxShape.circle),
              child: Icon(Icons.arrow_downward, size: 14, color: style.accent),
            ),
          ),
        if (shape.target != null)
          _DirectionCard(
            label: 'مقصد',
            kind: f.targetKind,
            wallet: tw,
            asset: ta,
            person: f.targetKind == 'person' ? personOf(f.targetId) : null,
            balance: targetBal,
            insufficient: false,
            optional: f.type == 'SELL',
            onTap: () => _pickEndpoint('target'),
          ),
        if (f.type == 'SELL' && (f.targetKind != null || f.targetId != null))
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: () => widget.onChange(f.copy()
                ..targetKind = null
                ..targetId = null
                ..targetAmount = ''),
              child: const Text('بدون ثبت مقصد', style: TextStyle(fontSize: 11, color: C.slate400)),
            ),
          ),
        const SizedBox(height: 16),
        const FieldLabel('تاریخ'),
        SelectBox(
          text: jd != null ? formatJalaaliHuman(jd) : (f.date.isEmpty ? 'انتخاب تاریخ' : f.date),
          leading: Icon(Icons.calendar_today_outlined, size: 16, color: style.accent),
          trailing: Icons.chevron_left,
          onTap: () async {
            final r = await showJalaliDatePicker(context, f.date);
            if (r != null) _setDate(r);
          },
        ),
        const SizedBox(height: 8),
        Row(children: [
          _chip('امروز', jd == today, () => _setDate(formatJalaali(today))),
          const SizedBox(width: 8),
          _chip('دیروز', jd == yesterday, () => _setDate(formatJalaali(yesterday))),
        ]),
        const SizedBox(height: 16),
        FieldLabel(primaryLabel),
        NumberInput(value: primary == 'source' ? f.sourceAmount : f.targetAmount, onChanged: _setPrimary),
        if (primary == 'source' && insufficient)
          const Padding(padding: EdgeInsets.only(top: 4), child: Text('موجودی مبدأ کافی نیست.', style: TextStyle(fontSize: 11, color: C.rose400))),
        if (canQuick) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Text('درصدی از موجودی:', style: TextStyle(fontSize: 11, color: C.slate500)),
            for (final p in [25, 50, 75, 100])
              _chip(p == 100 ? 'همه' : '$p٪', false, () => _setPrimary(canonicalNumber(srcBal * p / 100)), color: style.accent),
          ]),
        ],
        if (pricing.needsPrice) ...[
          const SizedBox(height: 16),
          if (pricing.showTomanPrice) ...[
            FieldLabel(pricing.priceLabel.isEmpty ? 'قیمت واحد (تومان)' : pricing.priceLabel),
            NumberInput(value: f.priceToman, onChanged: _setPrice),
            const SizedBox(height: 12),
          ],
          if (pricing.needsUsdRate) ...[
            const FieldLabel('نرخ دلار در لحظه (تومان)'),
            NumberInput(value: f.usdRate, onChanged: _setUsd),
          ],
        ],
        if (showDerived) ...[
          const SizedBox(height: 16),
          _DerivedLine(form: f, sw: sw, tw: tw, sa: sa, ta: ta),
        ],
        if (showCross) ...[
          const SizedBox(height: 16),
          FieldLabel('مقدار دریافتی${() {
            final un = tw != null ? currencyMeta(tw.currency).label : (ta?.unit ?? (f.targetKind == 'person' ? 'مقدار' : ''));
            return un.isNotEmpty ? ' ($un)' : '';
          }()}'),
          NumberInput(value: f.targetAmount, onChanged: (v) => widget.onChange(f.copy()..targetAmount = v)),
        ],
        if (shape.needsCategory != null) ...[
          const SizedBox(height: 16),
          FieldLabel(shape.needsCategory == 'income' ? 'دسته درآمد' : 'دسته هزینه'),
          Builder(builder: (_) {
            Category? sel;
            for (final c in s.categories) {
              if (c.id == f.categoryId) sel = c;
            }
            return SelectBox(
              text: sel?.name ?? '— انتخاب کنید —',
              placeholder: sel == null,
              leading: sel != null ? Dot(hexColor(sel.color)) : const Icon(Icons.folder_outlined, size: 15, color: C.slate500),
              trailing: Icons.chevron_left,
              onTap: () async {
                final r = await showCategoryPicker(context,
                    title: shape.needsCategory == 'income' ? 'انتخاب دسته درآمد' : 'انتخاب دسته هزینه',
                    kind: shape.needsCategory!,
                    categories: s.categories,
                    value: f.categoryId);
                if (r != null && r != kNone) widget.onChange(f.copy()..categoryId = r);
              },
            );
          }),
        ],
        const SizedBox(height: 16),
        const FieldLabel('توضیحات (اختیاری)'),
        AppTextField(value: f.note, maxLines: 3, onChanged: (v) => widget.onChange(f.copy()..note = v.length > 500 ? v.substring(0, 500) : v)),
        if (f.type == 'TRANSFER' && sw != null && tw != null && sw.currency != tw.currency)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Row(children: [
              Icon(Icons.swap_horiz, size: 13, color: C.amber300),
              SizedBox(width: 6),
              Expanded(child: Text('انتقال بین دو ارز متفاوت — هر دو مقدار را به‌صورت دستی وارد کن.', style: TextStyle(fontSize: 11, color: C.amber300))),
            ]),
          ),
      ]),
    );
  }

  Widget _chip(String label, bool active, VoidCallback onTap, {Color? color}) => InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: () {
          haptic();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(color: active ? C.white10 : C.white5, borderRadius: BorderRadius.circular(9)),
          child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color ?? (active ? Colors.white : C.slate400))),
        ),
      );
}

class _DirectionCard extends StatelessWidget {
  final String label;
  final String? kind;
  final Wallet? wallet;
  final Asset? asset;
  final Person? person;
  final double? balance;
  final bool insufficient, optional;
  final VoidCallback onTap;
  const _DirectionCard({required this.label, this.kind, this.wallet, this.asset, this.person, this.balance, required this.insufficient, required this.optional, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final filled = wallet != null || asset != null;
    final name = wallet?.name ?? asset?.name ?? person?.name ?? 'انتخاب کنید';
    final unit = wallet != null ? '${currencyMeta(wallet!.currency).symbol} ${wallet!.currency}' : (asset?.unit ?? '');
    String? sub;
    if (filled) {
      if (balance != null) {
        final b = wallet != null
            ? formatCurrencyAmount(balance, wallet!.currency)
            : asset != null
                ? formatAssetAmount(balance, asset!.decimalPlaces)
                : formatEnNumber(balance!, maxFrac: 6);
        sub = '$b ${unit.trim()}';
      } else {
        sub = kind == 'person' ? 'حساب شخص' : unit;
      }
    }
    final (bg, fg, ic) = switch (kind) {
      'asset' => (kAssetIconBg, kAssetIconFg, Icons.toll_outlined),
      'person' => (kPersonIconBg, kPersonIconFg, Icons.person_outline),
      _ => (kWalletIconBg, kWalletIconFg, Icons.account_balance_wallet_outlined),
    };
    return Material(
      color: C.raised,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          haptic();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: insufficient ? C.rose.withValues(alpha: 0.5) : (filled ? C.white10 : const Color(0x26FFFFFF))),
          ),
          child: Row(children: [
            EntityIcon(iconUrl: wallet?.iconUrl ?? asset?.iconUrl, fallback: ic, bgColor: bg, color: fg),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$label${optional ? ' · اختیاری' : ''}', style: const TextStyle(fontSize: 11, color: C.slate500)),
                Text(name, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: filled || person != null ? const Color(0xFFF1F5F9) : C.slate500)),
                if (sub != null) Money(sub, style: TextStyle(fontSize: 11, color: insufficient ? C.rose400 : C.slate500)),
              ]),
            ),
            const Icon(Icons.chevron_left, size: 18, color: C.slate500),
          ]),
        ),
      ),
    );
  }
}

class _DerivedLine extends StatelessWidget {
  final TxForm form;
  final Wallet? sw, tw;
  final Asset? sa, ta;
  const _DerivedLine({required this.form, this.sw, this.tw, this.sa, this.ta});
  @override
  Widget build(BuildContext context) {
    Wallet? w;
    Asset? a;
    String value;
    String label;
    if (form.type == 'BUY') {
      w = sw;
      value = form.sourceAmount;
      label = 'مبلغ پرداختی${w != null ? ' (${currencyMeta(w.currency).label})' : ''}';
    } else if (form.type == 'SELL') {
      w = tw;
      value = form.targetAmount;
      label = 'مبلغ دریافتی${w != null ? ' (${currencyMeta(w.currency).label})' : ''}';
    } else if (sw != null && ta != null) {
      a = ta;
      value = form.targetAmount;
      label = 'مقدار دریافتی${a!.unit.isNotEmpty ? ' (${a.unit})' : ''}';
    } else {
      w = tw;
      value = form.targetAmount;
      label = 'مبلغ دریافتی (${currencyMeta(w!.currency).label})';
    }
    final v = n(value);
    final display = value.isEmpty
        ? '—'
        : (w != null ? formatCurrencyAmount(v, w.currency) : (a != null ? formatAssetAmount(v, a.decimalPlaces) : formatEnNumber(v, maxFrac: 10)));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Icon(Icons.calculate_outlined, size: 13, color: C.slate400),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: C.slate400)),
        const Text(' — محاسبه‌شده', style: TextStyle(fontSize: 11, color: C.slate600)),
      ]),
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(color: C.white5, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.borderSoft)),
        child: Money(display, align: TextAlign.left, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: C.slate200)),
      ),
    ]);
  }
}

class _PreviewPanel extends StatelessWidget {
  final List<TxForm> rows;
  final PortfolioStore store;
  final TypeStyle style;
  const _PreviewPanel({required this.rows, required this.store, required this.style});
  @override
  Widget build(BuildContext context) {
    final valid = rows.map((r) => validateForm(r, store.wallets) == null).toList();
    final count = valid.where((v) => v).length;
    if (count == 0) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: C.white10, style: BorderStyle.solid)),
        child: const Text('پیش‌نمایش پس از تکمیل فرم در اینجا ظاهر می‌شود.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: C.slate500)),
      );
    }
    final byCur = <String, List<double>>{};
    if (rows.length > 1) {
      for (var i = 0; i < rows.length; i++) {
        if (!valid[i]) continue;
        final r = rows[i];
        if (r.sourceKind == 'wallet' && r.sourceId != null) {
          final w = findWallet(store.wallets, r.sourceId);
          if (w != null) (byCur[w.currency] ??= [0, 0])[1] += numOr0(n(r.sourceAmount));
        }
        if (r.targetKind == 'wallet' && r.targetId != null) {
          final w = findWallet(store.wallets, r.targetId);
          if (w != null) (byCur[w.currency] ??= [0, 0])[0] += numOr0(n(r.targetAmount));
        }
      }
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _accentBox(style.accent),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text('پیش‌نمایش', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: style.accent, letterSpacing: 1)),
          const Spacer(),
          if (rows.length > 1) Text('$count از ${rows.length} آماده', style: const TextStyle(fontSize: 11, color: C.slate500)),
        ]),
        const SizedBox(height: 8),
        for (var i = 0; i < rows.length; i++)
          if (valid[i])
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('${rows.length > 1 ? '#${i + 1} · ' : ''}${summarizeForm(rows[i], store.wallets, store.assets, store.categories, store.persons)}',
                  style: const TextStyle(fontSize: 13, color: C.slate200, height: 1.6)),
            ),
        for (final e in byCur.entries)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Row(children: [
                Text(e.key, style: const TextStyle(fontSize: 11, color: C.slate500)),
                const Spacer(),
                Text(
                  '${e.value[0] > 0 ? '+${formatCurrencyAmount(e.value[0], e.key)} ' : ''}${e.value[1] > 0 ? '-${formatCurrencyAmount(e.value[1], e.key)} ' : ''}= ${e.value[0] - e.value[1] >= 0 ? '+' : ''}${formatCurrencyAmount(e.value[0] - e.value[1], e.key)} ${currencyMeta(e.key).symbol}',
                  style: const TextStyle(fontSize: 11, color: C.slate300),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}

class _ConvertFormView extends StatelessWidget {
  final ConvertForm form;
  final ValueChanged<ConvertForm> onChange;
  final PortfolioStore store;
  const _ConvertFormView({required this.form, required this.onChange, required this.store});

  @override
  Widget build(BuildContext context) {
    final s = store;
    final sa = findAsset(s.assets, form.sourceAssetId);
    final ta = findAsset(s.assets, form.targetAssetId);
    final sw = findWallet(s.wallets, form.sellTargetWalletId);
    final bw = findWallet(s.wallets, form.buySourceWalletId);
    final eff = applyMatchBuyValue(form);
    final holding = form.sourceAssetId != null ? assetHolding(form.sourceAssetId!, s.transactions) : null;
    final warning = convertValueWarning(eff);
    final sq = n(eff.sourceAmount), bq = n(eff.targetAmount), sp = n(eff.sellPriceToman), bp = n(eff.buyPriceToman);
    final sellTotal = sq > 0 && sp > 0 ? sq * sp : 0.0;
    final buyTotal = bq > 0 && bp > 0 ? bq * bp : 0.0;
    const accent = Color(0xFF7C3AED);

    Future<String?> pickAsset(String title, String? exclude) async {
      final r = await showEndpointPicker(context,
          title: title, allow: const ['asset'], excludeIds: exclude != null ? [exclude] : const [], wallets: s.wallets, assets: s.assets, persons: const [], transactions: s.transactions);
      return r?.$2;
    }

    Future<String?> pickWallet(String title) async {
      final r = await showEndpointPicker(context, title: title, allow: const ['wallet'], wallets: s.wallets, assets: s.assets, persons: const [], transactions: s.transactions);
      return r?.$2;
    }

    Widget endpoint(String label, Asset? a, Color bg, Color fg, VoidCallback onTap) => AppCard(
          padding: const EdgeInsets.all(12),
          radius: 14,
          onTap: onTap,
          child: Row(children: [
            EntityIcon(iconUrl: a?.iconUrl, fallback: Icons.toll_outlined, bgColor: bg, color: fg, size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: const TextStyle(fontSize: 11, color: C.slate500)),
                Text(a?.name ?? 'انتخاب دارایی', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: a != null ? Colors.white : C.slate500)),
              ]),
            ),
            const Icon(Icons.chevron_left, size: 18, color: C.slate500),
          ]),
        );

    Widget walletRow(String label, Wallet? w, VoidCallback onPick, VoidCallback onClear) => Row(children: [
          Expanded(
            child: InkWell(
              onTap: onPick,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(children: [
                  Expanded(child: Text(label, style: const TextStyle(fontSize: 12, color: C.slate400))),
                  const Icon(Icons.account_balance_wallet_outlined, size: 13, color: C.slate400),
                  const SizedBox(width: 4),
                  Text(w?.name ?? 'بدون ثبت', style: const TextStyle(fontSize: 12, color: C.slate200)),
                ]),
              ),
            ),
          ),
          if (w != null) TextButton(onPressed: onClear, child: const Text('حذف', style: TextStyle(fontSize: 11, color: C.rose300))),
        ]);

    Widget numField(String label, String value, ValueChanged<String> onCh, {bool disabled = false}) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [FieldLabel(label), NumberInput(value: value, onChanged: onCh, enabled: !disabled)]),
        );

    final jd = parseJalaali(form.date);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _accentBox(accent),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Row(children: [
          Icon(Icons.swap_horiz, size: 16, color: Color(0xFFA78BFA)),
          SizedBox(width: 6),
          Text('تبدیل دارایی', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
        ]),
        const SizedBox(height: 6),
        const Text('یک فروش از دارایی مبدأ و یک خرید برای دارایی مقصد ثبت می‌شود؛ قیمت‌ها و نرخ دلار برای گزارش‌ها ذخیره می‌شوند.',
            style: TextStyle(fontSize: 11, color: C.slate400, height: 1.6)),
        const SizedBox(height: 12),
        SelectBox(
          text: 'تاریخ: ${jd != null ? formatJalaaliHuman(jd) : form.date}',
          trailing: Icons.calendar_today_outlined,
          onTap: () async {
            final r = await showJalaliDatePicker(context, form.date);
            if (r != null) onChange(form.copy()..date = r);
          },
        ),
        const SizedBox(height: 16),
        const Text('فروش (مبدأ)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: C.amber300)),
        const SizedBox(height: 8),
        endpoint('دارایی مبدأ', sa, const Color(0x1FD97706), kAssetIconFg, () async {
          final id = await pickAsset('دارایی مبدأ', form.targetAssetId);
          if (id == null) return;
          final a = findAsset(s.assets, id);
          onChange(form.copy()
            ..sourceAssetId = id
            ..sellPriceToman = a != null ? jsNumStr(a.priceToman) : form.sellPriceToman);
        }),
        if (holding != null && sa != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('موجودی: ${formatAssetAmount(holding, sa.decimalPlaces)} ${sa.unit}', style: const TextStyle(fontSize: 11, color: C.slate500)),
          ),
        numField('مقدار فروش${sa != null ? ' (${sa.unit})' : ''}', form.sourceAmount, (v) => onChange(form.copy()..sourceAmount = v)),
        numField('قیمت فروش هر واحد (تومان)', form.sellPriceToman, (v) => onChange(form.copy()..sellPriceToman = v)),
        numField('نرخ دلار (فروش)', form.sellUsdRate, (v) => onChange(form.copy()..sellUsdRate = v)),
        walletRow('کیف پول مقصد فروش (اختیاری)', sw, () async {
          final id = await pickWallet('کیف پول مقصد فروش');
          if (id != null) onChange(form.copy()..sellTargetWalletId = id);
        }, () => onChange(form.copy()..sellTargetWalletId = null)),
        const Divider(height: 28),
        const Text('خرید (مقصد)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: C.purple300)),
        const SizedBox(height: 8),
        endpoint('دارایی مقصد', ta, kWalletIconBg, kWalletIconFg, () async {
          final id = await pickAsset('دارایی مقصد', form.sourceAssetId);
          if (id == null) return;
          final a = findAsset(s.assets, id);
          onChange(form.copy()
            ..targetAssetId = id
            ..buyPriceToman = a != null ? jsNumStr(a.priceToman) : form.buyPriceToman);
        }),
        numField('مقدار خرید${ta != null ? ' (${ta.unit})' : ''}', form.targetAmount, (v) => onChange(form.copy()..targetAmount = v)),
        numField('قیمت خرید هر واحد (تومان)', eff.buyPriceToman, (v) => onChange(form.copy()..buyPriceToman = v), disabled: form.matchBuyValue),
        numField('نرخ دلار (خرید)', eff.buyUsdRate, (v) => onChange(form.copy()..buyUsdRate = v), disabled: form.matchBuyValue),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: form.matchBuyValue,
          onChanged: (v) => onChange(form.copy()..matchBuyValue = v ?? false),
          title: const Text('هم‌ارزش با فروش (قیمت خرید خودکار)', style: TextStyle(fontSize: 12, color: C.slate300)),
        ),
        walletRow('کیف پول مبدأ خرید (اختیاری)', bw, () async {
          final id = await pickWallet('کیف پول مبدأ خرید');
          if (id != null) onChange(form.copy()..buySourceWalletId = id);
        }, () => onChange(form.copy()..buySourceWalletId = null)),
        if (sellTotal > 0 || buyTotal > 0) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: StatPill(label: 'ارزش فروش', value: formatCurrency(sellTotal, 'TOMAN'))),
            const SizedBox(width: 8),
            Expanded(child: StatPill(label: 'ارزش خرید', value: formatCurrency(buyTotal, 'TOMAN'))),
          ]),
        ],
        if (warning != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(warning, style: const TextStyle(fontSize: 11, color: C.amber300))),
        const SizedBox(height: 12),
        AppTextField(value: form.note, onChanged: (v) => onChange(form.copy()..note = v), hint: 'یادداشت (اختیاری)', maxLines: 2),
      ]),
    );
  }
}
