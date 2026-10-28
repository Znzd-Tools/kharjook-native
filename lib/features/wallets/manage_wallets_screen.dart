// Port of ManageWalletsView.tsx.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LengthLimitingTextInputFormatter;
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/models.dart';
import '../../core/store.dart';
import '../../core/ui/icon_picker.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/toast.dart';
import '../../core/ui/widgets.dart';
import '../../core/utils/format.dart';
import '../transactions/endpoint_picker.dart';
import '../transactions/tx_logic.dart';

class ManageWalletsScreen extends StatefulWidget {
  const ManageWalletsScreen({super.key});
  @override
  State<ManageWalletsScreen> createState() => _ManageWalletsScreenState();
}

class _ManageWalletsScreenState extends State<ManageWalletsScreen> {
  String? editingId;
  String name = '', currency = 'IRT', initialBalance = '';
  String? iconUrl;
  bool submitting = false;
  String? archivingId;
  final pending = <String>{};
  int formKey = 0;

  SupabaseClient get _c => Supabase.instance.client;

  void _reset() => setState(() {
        editingId = null;
        name = '';
        currency = 'IRT';
        initialBalance = '';
        iconUrl = null;
        formKey++;
      });

  void _edit(Wallet w) => setState(() {
        editingId = w.id;
        name = w.name;
        currency = w.currency;
        initialBalance = jsNumStr(w.initialBalance);
        iconUrl = w.iconUrl;
        formKey++;
      });

  Future<void> _submit(PortfolioStore s) async {
    final nm = name.trim();
    final initial = canonicalToNumber(initialBalance.isEmpty ? '0' : initialBalance);
    if (nm.isEmpty || initial.isNaN) return;
    final user = s.user!;
    Future<void> execute() async {
      final snapshot = s.wallets;
      if (editingId != null) {
        final id = editingId!;
        final patch = {'name': nm, 'initial_balance': initial, 'icon_url': iconUrl};
        setState(() => pending.add(id));
        try {
          final data = await _c.from('wallets').update(patch).eq('id', id).select().single();
          final saved = Wallet.fromJson(data);
          s.update((st) => st.wallets = st.wallets.map((w) => w.id == id ? saved : w).toList());
        } catch (e) {
          s.update((st) => st.wallets = snapshot);
          rethrow;
        } finally {
          if (mounted) setState(() => pending.remove(id));
        }
      } else {
        final nextOrder = s.wallets.fold(-1, (m, w) => (w.orderIndex ?? -1) > m ? (w.orderIndex ?? -1) : m) + 1;
        final tempId = 'temp-wallet-${const Uuid().v4()}';
        final opt = Wallet(
            id: tempId, userId: user.id, name: nm, currency: currency, initialBalance: initial, iconUrl: iconUrl, orderIndex: nextOrder, createdAt: DateTime.now().toUtc().toIso8601String());
        setState(() => pending.add(tempId));
        s.update((st) => st.wallets = [...st.wallets, opt]);
        try {
          final data = await _c
              .from('wallets')
              .insert([
                {'user_id': user.id, 'name': nm, 'currency': currency, 'initial_balance': initial, 'icon_url': iconUrl, 'order_index': nextOrder}
              ])
              .select()
              .single();
          final saved = Wallet.fromJson(data);
          s.update((st) => st.wallets = st.wallets.map((w) => w.id == tempId ? saved : w).toList());
        } catch (e) {
          s.update((st) => st.wallets = snapshot);
          rethrow;
        } finally {
          if (mounted) setState(() => pending.remove(tempId));
        }
      }
      _reset();
    }

    setState(() => submitting = true);
    try {
      await execute();
    } catch (_) {
      Toast.error('خطا در ثبت کیف پول.', actionLabel: 'تلاش مجدد', onAction: () => execute().catchError((_) {}));
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<void> _persistOrder(PortfolioStore s, List<Wallet> ordered) async {
    try {
      await Future.wait([for (var i = 0; i < ordered.length; i++) _c.from('wallets').update({'order_index': i}).eq('id', ordered[i].id)]);
    } catch (_) {
      Toast.error('ذخیره ترتیب کیف پول‌ها ناموفق بود.');
      try {
        final data = await _c.from('wallets').select().isFilter('archived_at', null).order('order_index', ascending: true, nullsFirst: false).order('created_at', ascending: true);
        s.update((st) => st.wallets = (data as List).cast<Json>().map(Wallet.fromJson).toList());
      } catch (_) {}
    }
  }

  Future<void> _archive(PortfolioStore s, Wallet w) async {
    if (!await confirmDialog(context,
        message: '«${w.name}» بایگانی می‌شود و دیگر در فهرست‌ها نمایش داده نمی‌شود. تراکنش‌های قبلی دست‌نخورده باقی می‌ماند. ادامه می‌دهی؟', danger: true, confirmLabel: 'حذف')) {
      return;
    }
    Future<void> execute() async {
      final snapshot = s.wallets;
      setState(() {
        archivingId = w.id;
        pending.add(w.id);
      });
      s.update((st) => st.wallets = st.wallets.where((x) => x.id != w.id).toList());
      try {
        await _c.from('wallets').update({'archived_at': DateTime.now().toUtc().toIso8601String()}).eq('id', w.id);
        if (w.iconUrl != null) await deleteEntityIcon(w.iconUrl);
        if (editingId == w.id) _reset();
      } catch (e) {
        s.update((st) => st.wallets = snapshot);
        rethrow;
      } finally {
        if (mounted) {
          setState(() {
            pending.remove(w.id);
            archivingId = null;
          });
        }
      }
    }

    try {
      await execute();
    } catch (_) {
      Toast.error('خطا در بایگانی.', actionLabel: 'تلاش مجدد', onAction: () => execute().catchError((_) {}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<PortfolioStore>();
    final user = s.user;
    if (user == null) return const SizedBox.shrink();
    return SubPage(
      title: 'مدیریت کیف پول‌ها',
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
        AppCard(
          key: ValueKey('form$formKey'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(editingId != null ? 'ویرایش کیف پول' : 'کیف پول جدید', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white))),
              if (editingId != null) TextButton.icon(onPressed: _reset, icon: const Icon(Icons.close, size: 14), label: const Text('انصراف')),
            ]),
            const SizedBox(height: 12),
            IconPickerField(
              value: iconUrl,
              onChanged: (u) => setState(() => iconUrl = u),
              userId: user.id,
              folder: 'wallets',
              fallback: Icons.account_balance_wallet_outlined,
              bgColor: const Color(0x1FA855F7),
              label: 'آیکون (اختیاری)',
            ),
            const SizedBox(height: 14),
            Field(
              label: 'نام',
              child: AppTextField(value: name, onChanged: (v) => name = v, hint: 'مثلا: ملی، صرافی نوبیتکس، نقد دلاری', formatters: [LengthLimitingTextInputFormatter(64)]),
            ),
            const FieldLabel('ارز'),
            Row(children: [
              for (final c in kCurrencies)
                Expanded(
                  child: Opacity(
                    opacity: editingId != null && currency != c ? 0.3 : 1,
                    child: GestureDetector(
                      onTap: editingId != null ? null : () => setState(() => currency = c),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: currency == c ? C.purple : C.hover,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: currency == c ? C.purple500 : C.white10),
                        ),
                        child: Column(children: [
                          Text(currencyMeta(c).symbol, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                          Text(c, style: const TextStyle(fontSize: 11, color: C.slate300)),
                        ]),
                      ),
                    ),
                  ),
                ),
            ]),
            if (editingId != null) const Padding(padding: EdgeInsets.only(top: 6), child: Text('ارز پس از ساخت قابل تغییر نیست.', style: TextStyle(fontSize: 11, color: C.slate500))),
            const SizedBox(height: 14),
            Field(label: 'موجودی اولیه (${currencyMeta(currency).label})', child: NumberInput(value: initialBalance, onChanged: (v) => initialBalance = v)),
            AppButton(submitting ? 'در حال ثبت...' : (editingId != null ? 'ثبت تغییرات' : 'افزودن کیف پول'),
                variant: editingId != null ? BtnVariant.primary : BtnVariant.secondary, expand: true, onPressed: submitting ? null : () => _submit(s)),
          ]),
        ),
        const SizedBox(height: 16),
        if (s.wallets.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('هنوز کیف پولی نساخته‌ای.', textAlign: TextAlign.center, style: TextStyle(color: C.slate500, fontSize: 12))),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderStart: (_) => haptic('light'),
          onReorder: (from, to) {
            haptic();
            final list = [...s.wallets];
            if (to > from) to -= 1;
            final item = list.removeAt(from);
            list.insert(to, item);
            final ordered = [for (var i = 0; i < list.length; i++) list[i].withOrder(i)];
            s.update((st) => st.wallets = ordered);
            _persistOrder(s, ordered);
          },
          children: [
            for (var i = 0; i < s.wallets.length; i++)
              Padding(
                key: ValueKey(s.wallets[i].id),
                padding: const EdgeInsets.only(bottom: 8),
                child: Opacity(
                  opacity: pending.contains(s.wallets[i].id) ? 0.6 : 1,
                  child: AppCard(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      ReorderableDragStartListener(index: i, child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.drag_indicator, size: 18, color: C.slate500))),
                      const SizedBox(width: 6),
                      EntityIcon(iconUrl: s.wallets[i].iconUrl, fallback: Icons.account_balance_wallet_outlined, bgColor: const Color(0x1AA855F7), color: kWalletIconFg, size: 38),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(s.wallets[i].name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.slate200)),
                          Money('${currencyMeta(s.wallets[i].currency).symbol} ${formatCurrencyAmount(s.wallets[i].initialBalance, s.wallets[i].currency)} · ${s.wallets[i].currency}',
                              style: const TextStyle(fontSize: 11, color: C.slate500)),
                        ]),
                      ),
                      IconButton(icon: const Icon(Icons.edit_outlined, size: 17, color: C.slate400), onPressed: pending.contains(s.wallets[i].id) ? null : () => _edit(s.wallets[i])),
                      IconButton(
                        icon: const Icon(Icons.archive_outlined, size: 17, color: C.rose300),
                        onPressed: archivingId == s.wallets[i].id || pending.contains(s.wallets[i].id) ? null : () => _archive(s, s.wallets[i]),
                      ),
                    ]),
                  ),
                ),
              ),
          ],
        ),
      ]),
    );
  }
}
