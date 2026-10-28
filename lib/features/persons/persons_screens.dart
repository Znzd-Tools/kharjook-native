// Ports of ManagePersonsView.tsx, PersonDetailView.tsx and
// persons/utils/person-settle-prefill.ts.

import 'package:flutter/material.dart';
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

Wallet? pickDefaultSettleWallet(List<Wallet> wallets) {
  final active = stableSorted(wallets.where((w) => w.archivedAt == null).toList(), (a, b) => (a.orderIndex ?? 0) - (b.orderIndex ?? 0));
  return active.where((w) => w.currency == 'IRT').firstOrNull ?? active.firstOrNull;
}

String? personSettleSide(double balance) => balance > 0 ? 'source' : (balance < 0 ? 'target' : null);

String? buildPersonSettleTransactionUrl({required String personId, required String walletId, required double balance}) {
  final side = personSettleSide(balance);
  if (side == null) return null;
  final abs = balance.abs();
  if (!abs.isFinite || abs <= 0) return null;
  final amount = abs.toStringAsFixed(10).replaceFirst(RegExp(r'\.?0+$'), '');
  final q = Uri(queryParameters: {'type': 'TRANSFER', 'personId': personId, 'walletId': walletId, 'amount': amount, 'personSide': side}).query;
  return '/transactions/new?$q';
}

String _personStatus(double b) => b > 0 ? 'بدهکار' : (b < 0 ? 'بستانکار' : 'تسویه');
Color _personTone(double b) => b > 0 ? C.amber300 : (b < 0 ? const Color(0xFF67E8F9) : C.slate400);
String _abs6(double b) => formatEnNumber(b.abs(), maxFrac: 6);

class ManagePersonsScreen extends StatefulWidget {
  const ManagePersonsScreen({super.key});
  @override
  State<ManagePersonsScreen> createState() => _ManagePersonsScreenState();
}

class _ManagePersonsScreenState extends State<ManagePersonsScreen> {
  String? editingId;
  String name = '';
  int formKey = 0;
  bool submitting = false;
  SupabaseClient get _c => Supabase.instance.client;

  void _reset() => setState(() {
        editingId = null;
        name = '';
        formKey++;
      });

  Future<void> _submit(PortfolioStore s) async {
    final user = s.user;
    if (user == null) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      Toast.error('نام شخص الزامی است.');
      return;
    }
    setState(() => submitting = true);
    try {
      if (editingId != null) {
        final id = editingId!;
        final data = await _c.from('persons').update({'name': trimmed}).eq('id', id).select().single();
        final p = Person.fromJson(data);
        s.update((st) => st.persons = [for (final x in st.persons) x.id == id ? p : x]);
        Toast.success('شخص ویرایش شد.');
      } else {
        final nextOrder = s.persons.fold<int>(-1, (m, p) => p.orderIndex != null && p.orderIndex! > m ? p.orderIndex! : m) + 1;
        final data = await _c.from('persons').insert({'user_id': user.id, 'name': trimmed, 'order_index': nextOrder}).select().single();
        final p = Person.fromJson(data);
        s.update((st) => st.persons = [...st.persons, p]);
        Toast.success('شخص ثبت شد.');
      }
      _reset();
    } catch (_) {
      Toast.error('خطا در ثبت شخص.');
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<void> _persistOrder(PortfolioStore s, List<Person> ordered) async {
    try {
      await Future.wait([for (var i = 0; i < ordered.length; i++) _c.from('persons').update({'order_index': i}).eq('id', ordered[i].id)]);
    } catch (_) {
      Toast.error('ذخیره ترتیب اشخاص ناموفق بود.');
      try {
        final data = await _c.from('persons').select().order('order_index', ascending: true, nullsFirst: false).order('created_at', ascending: true);
        s.update((st) => st.persons = (data as List).cast<Json>().map(Person.fromJson).toList());
      } catch (_) {}
    }
  }

  Future<void> _delete(PortfolioStore s, Person p) async {
    final used = s.transactions.any((t) => t.sourcePersonId == p.id || t.targetPersonId == p.id);
    if (used) {
      Toast.error('این شخص در تراکنش‌ها استفاده شده و قابل حذف نیست.');
      return;
    }
    if (!await confirmDialog(context, message: 'آیا از حذف این شخص مطمئن هستید؟', danger: true, confirmLabel: 'حذف')) return;
    try {
      await _c.from('persons').delete().eq('id', p.id);
      s.update((st) => st.persons = st.persons.where((x) => x.id != p.id).toList());
      if (editingId == p.id) _reset();
      Toast.success('شخص حذف شد.');
    } catch (_) {
      Toast.error('خطا در حذف شخص.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<PortfolioStore>();
    if (s.user == null) return const SizedBox.shrink();
    final persons = s.persons;
    return SubPage(
      title: 'اشخاص',
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(editingId != null ? 'ویرایش شخص' : 'ثبت شخص جدید', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.purple400))),
              if (editingId != null) TextButton.icon(onPressed: _reset, icon: const Icon(Icons.close, size: 14), label: const Text('انصراف')),
            ]),
            const SizedBox(height: 10),
            AppTextField(key: ValueKey('name$formKey'), value: name, onChanged: (v) => name = v, hint: 'نام شخص'),
            const SizedBox(height: 12),
            AppButton(submitting ? 'در حال ثبت...' : (editingId != null ? 'ثبت تغییرات' : 'ذخیره شخص'), icon: Icons.add, expand: true, onPressed: submitting ? null : () => _submit(s)),
          ]),
        ),
        const SizedBox(height: 16),
        const Text('لیست اشخاص', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.slate400)),
        const SizedBox(height: 10),
        if (persons.isEmpty)
          const EmptyState(icon: Icons.person_outline, title: 'هنوز شخصی ثبت نشده.', description: 'از فرم بالا اولین شخص را اضافه کن.')
        else
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderStart: (_) => haptic('light'),
            onReorder: (from, to) {
              haptic();
              final list = [...persons];
              if (to > from) to -= 1;
              list.insert(to, list.removeAt(from));
              final ordered = [
                for (var i = 0; i < list.length; i++) Person(id: list[i].id, userId: list[i].userId, name: list[i].name, orderIndex: i, createdAt: list[i].createdAt),
              ];
              s.update((st) => st.persons = ordered);
              _persistOrder(s, ordered);
            },
            children: [
              for (var i = 0; i < persons.length; i++)
                Builder(
                  key: ValueKey(persons[i].id),
                  builder: (_) {
                    final p = persons[i];
                    final b = calculatePersonBalance(p, s.transactions);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AppCard(
                        padding: const EdgeInsets.all(12),
                        borderColor: editingId == p.id ? C.purple500 : null,
                        child: Row(children: [
                          ReorderableDragStartListener(index: i, child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.drag_indicator, size: 18, color: C.slate500))),
                          const SizedBox(width: 6),
                          const EntityIcon(fallback: Icons.person_outline, size: 38),
                          const SizedBox(width: 10),
                          Expanded(
                            child: InkWell(
                              onTap: () => Nav.push(context, '/deadlines/persons/${p.id}'),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(p.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: C.slate200)),
                                const SizedBox(height: 2),
                                Text('${_personStatus(b)} · ${_abs6(b)}', style: TextStyle(fontSize: 11, color: _personTone(b))),
                              ]),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 17, color: C.slate400),
                            onPressed: () => setState(() {
                              editingId = p.id;
                              name = p.name;
                              formKey++;
                            }),
                          ),
                          IconButton(icon: const Icon(Icons.delete_outline, size: 17, color: C.rose300), onPressed: () => _delete(s, p)),
                        ]),
                      ),
                    );
                  },
                ),
            ],
          ),
      ]),
    );
  }
}

const _typeLabels = {'BUY': 'خرید', 'SELL': 'فروش', 'TRANSFER': 'انتقال', 'INCOME': 'درآمد', 'EXPENSE': 'هزینه', 'CONVERT': 'تبدیل'};

class PersonDetailScreen extends StatelessWidget {
  final String personId;
  const PersonDetailScreen({super.key, required this.personId});

  Future<void> _deleteTx(BuildContext context, PortfolioStore s, String id) async {
    if (!await confirmDialog(context, message: 'این تراکنش حذف شود؟', danger: true, confirmLabel: 'حذف')) return;
    try {
      await Supabase.instance.client.from('transactions').delete().eq('id', id);
      s.update((st) => st.transactions = st.transactions.where((t) => t.id != id).toList());
      Toast.success('تراکنش حذف شد.');
    } catch (_) {
      Toast.error('خطا در حذف تراکنش.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<PortfolioStore>();
    final person = s.persons.where((p) => p.id == personId).firstOrNull;
    if (person == null) return const SubPage(title: '', body: Center(child: Text('شخص پیدا نشد.', style: TextStyle(color: C.slate400))));
    final balance = calculatePersonBalance(person, s.transactions);
    final txs = stableSorted(s.transactions.where((t) => t.sourcePersonId == person.id || t.targetPersonId == person.id).toList(), (a, b) => b.dateString.compareTo(a.dateString));

    void openSettle() {
      final w = pickDefaultSettleWallet(s.wallets);
      if (w == null) {
        Toast.error('برای تسویه ابتدا یک کیف پول فعال بساز.');
        return;
      }
      final url = buildPersonSettleTransactionUrl(personId: person.id, walletId: w.id, balance: balance);
      if (url == null) {
        Toast.info('این شخص تسویه است.');
        return;
      }
      Nav.push(context, url);
    }

    return SubPage(
      title: person.name,
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
        AppCard(
          child: Column(children: [
            const EntityIcon(fallback: Icons.person_outline, size: 52),
            const SizedBox(height: 10),
            const Text('مانده حساب', style: TextStyle(fontSize: 12, color: C.slate400)),
            const SizedBox(height: 4),
            Money(_abs6(balance), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white)),
            Text(_personStatus(balance), style: TextStyle(fontSize: 13, color: _personTone(balance))),
            if (balance != 0) ...[
              const SizedBox(height: 12),
              AppButton(balance > 0 ? 'دریافت تسویه' : 'پرداخت تسویه', icon: Icons.handshake_outlined, expand: true, onPressed: openSettle),
            ],
          ]),
        ),
        const SizedBox(height: 16),
        const Text('تراکنش‌ها', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.slate400)),
        const SizedBox(height: 10),
        if (txs.isEmpty)
          const EmptyState(icon: Icons.swap_horiz, title: 'تراکنشی با این شخص نیست.', description: 'از ثبت تراکنش، این شخص را در مبدأ یا مقصد انتخاب کن.')
        else
          for (final tx in txs) _txRow(context, s, tx, person.id),
      ]),
    );
  }

  Widget _txRow(BuildContext context, PortfolioStore s, Transaction tx, String pid) {
    final isOut = tx.sourcePersonId == pid;
    final amount = (isOut ? tx.sourceAmount : tx.targetAmount) ?? 0;
    final tone = isOut ? const Color(0xFFFB7185) : const Color(0xFF34D399);
    final icon = tx.type == 'TRANSFER' ? Icons.swap_horiz : (isOut ? Icons.north_east : Icons.south_east);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: tone.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 16, color: tone),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_typeLabels[tx.type] ?? tx.type, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.slate200)),
                Text(_counterparty(s, tx, pid), style: const TextStyle(fontSize: 11, color: C.slate500)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Money('${isOut ? '-' : '+'}${_abs6(amount)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: tone)),
              Text(latinizeDigits(tx.dateString), style: const TextStyle(fontSize: 10, color: C.slate500)),
            ]),
          ]),
          Row(children: [
            Expanded(child: Text(tx.note ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: C.slate500))),
            IconButton(icon: const Icon(Icons.edit_outlined, size: 16, color: C.slate400), onPressed: () => Nav.push(context, '/transactions/${tx.id}/edit')),
            IconButton(icon: const Icon(Icons.delete_outline, size: 16, color: C.rose300), onPressed: () => _deleteTx(context, s, tx.id)),
          ]),
        ]),
      ),
    );
  }

  String _counterparty(PortfolioStore s, Transaction tx, String pid) {
    String? nameOf(List list, String? id, String fallback) => id == null ? null : (list.where((x) => x.id == id).map((x) => x.name as String).firstOrNull ?? fallback);
    if (tx.sourcePersonId == pid) {
      final r = nameOf(s.wallets, tx.targetWalletId, 'کیف پول') ?? nameOf(s.assets, tx.targetAssetId, 'دارایی') ?? (tx.targetPersonId != null ? 'شخص دیگر' : null);
      if (r != null) return r;
    } else {
      final r = nameOf(s.wallets, tx.sourceWalletId, 'کیف پول') ?? nameOf(s.assets, tx.sourceAssetId, 'دارایی') ?? (tx.sourcePersonId != null ? 'شخص دیگر' : null);
      if (r != null) return r;
    }
    if (tx.categoryId != null) return s.categories.where((c) => c.id == tx.categoryId).map((c) => c.name).firstOrNull ?? '';
    return '—';
  }
}
