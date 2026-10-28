// Port of ManageAssetsView.tsx.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../app/router.dart';
import '../../core/models.dart';
import '../../core/services/prices.dart';
import '../../core/store.dart';
import '../../core/ui/category_picker.dart';
import '../../core/ui/icon_picker.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/toast.dart';
import '../../core/ui/widgets.dart';

class ManageAssetsScreen extends StatefulWidget {
  const ManageAssetsScreen({super.key});
  @override
  State<ManageAssetsScreen> createState() => _ManageAssetsScreenState();
}

class _ManageAssetsScreenState extends State<ManageAssetsScreen> {
  String? editingId;
  String name = '', unit = '', categoryId = '', priceSourceId = '';
  int decimalPlaces = 4;
  String? iconUrl;
  bool includePnl = true, includeBalance = true, showAdvanced = false, submitting = false;
  final pending = <String>{};
  int formKey = 0;
  final _scroll = ScrollController();

  SupabaseClient get _c => Supabase.instance.client;

  void _reset() => setState(() {
        editingId = null;
        showAdvanced = false;
        name = '';
        unit = '';
        decimalPlaces = 4;
        categoryId = '';
        iconUrl = null;
        priceSourceId = '';
        includePnl = true;
        includeBalance = true;
        formKey++;
      });

  void _edit(Asset a) {
    setState(() {
      editingId = a.id;
      name = a.name;
      unit = a.unit;
      decimalPlaces = a.decimalPlaces;
      categoryId = a.categoryId ?? '';
      iconUrl = a.iconUrl;
      priceSourceId = a.priceSourceId ?? '';
      includePnl = a.includeInProfitLoss;
      includeBalance = a.includeInBalance ?? true;
      showAdvanced = decimalPlaces != 4 || !includePnl || !includeBalance;
      formKey++;
    });
    _scroll.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  Future<void> _submit(PortfolioStore s) async {
    if (name.trim().isEmpty || unit.trim().isEmpty) {
      Toast.error('نام و واحد دارایی الزامی است.');
      return;
    }
    final user = s.user!;
    Future<void> execute() async {
      final dp = decimalPlaces.clamp(0, 12);
      final payload = <String, dynamic>{
        'category_id': categoryId.isEmpty ? null : categoryId,
        'name': name,
        'unit': unit,
        'decimal_places': dp,
        'icon_url': iconUrl,
        'price_source_id': priceSourceId.isEmpty ? null : priceSourceId,
        'include_in_profit_loss': includePnl,
        'include_in_balance': includeBalance,
      };
      final snapshot = s.assets;
      if (editingId != null) {
        final id = editingId!;
        setState(() => pending.add(id));
        try {
          final data = await _c.from('assets').update(payload).eq('id', id).select().single();
          final saved = Asset.fromJson(data);
          s.update((st) => st.assets = st.assets.map((a) => a.id == id ? saved : a).toList());
        } catch (e) {
          s.update((st) => st.assets = snapshot);
          rethrow;
        } finally {
          if (mounted) setState(() => pending.remove(id));
        }
      } else {
        final nextOrder = s.assets.fold(-1, (m, a) => (a.orderIndex ?? -1) > m ? (a.orderIndex ?? -1) : m) + 1;
        final tempId = 'temp-asset-${const Uuid().v4()}';
        final opt = Asset.fromJson({...payload, 'id': tempId, 'user_id': user.id, 'price_toman': 0, 'price_usd': 0, 'order_index': nextOrder});
        setState(() => pending.add(tempId));
        s.update((st) => st.assets = [...st.assets, opt]);
        try {
          final data = await _c.from('assets').insert([
            {...payload, 'user_id': user.id, 'price_toman': 0, 'price_usd': 0, 'order_index': nextOrder}
          ]).select().single();
          final saved = Asset.fromJson(data);
          s.update((st) => st.assets = st.assets.map((a) => a.id == tempId ? saved : a).toList());
        } catch (e) {
          s.update((st) => st.assets = snapshot);
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
      Toast.error('ثبت دارایی ناموفق بود.', actionLabel: 'تلاش مجدد', onAction: () => execute().catchError((_) {}));
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<void> _delete(PortfolioStore s, String id) async {
    if (!await confirmDialog(context,
        message: '⚠️ هشدار جدی:\nبا پاک کردن این دارایی، تمام تراکنش‌های متصل به آن (خرید، فروش و...) برای همیشه پاک خواهند شد!\nآیا مطمئن هستید؟',
        danger: true,
        confirmLabel: 'حذف')) {
      return;
    }
    Future<void> execute() async {
      final snapshot = s.assets;
      final asset = snapshot.where((a) => a.id == id).firstOrNull;
      setState(() => pending.add(id));
      s.update((st) => st.assets = st.assets.where((a) => a.id != id).toList());
      try {
        await _c.from('assets').delete().eq('id', id);
        if (asset?.iconUrl != null) await deleteEntityIcon(asset!.iconUrl);
        if (editingId == id) _reset();
      } catch (e) {
        s.update((st) => st.assets = snapshot);
        rethrow;
      } finally {
        if (mounted) setState(() => pending.remove(id));
      }
    }

    try {
      await execute();
    } catch (_) {
      Toast.error('حذف دارایی ناموفق بود.', actionLabel: 'تلاش مجدد', onAction: () => execute().catchError((_) {}));
    }
  }

  Future<void> _persistOrder(PortfolioStore s, List<Asset> ordered) async {
    try {
      await Future.wait([for (var i = 0; i < ordered.length; i++) _c.from('assets').update({'order_index': i}).eq('id', ordered[i].id)]);
    } catch (_) {
      Toast.error('ذخیره ترتیب دارایی‌ها ناموفق بود.');
      try {
        final data = await _c.from('assets').select().order('order_index', ascending: true, nullsFirst: false).order('created_at', ascending: true);
        s.update((st) => st.assets = (data as List).cast<Json>().map(Asset.fromJson).toList());
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<PortfolioStore>();
    final user = s.user;
    if (user == null) return const SizedBox.shrink();
    final catalog = s.priceSourceCatalog;
    final selCat = categoryId.isEmpty ? null : s.categories.where((c) => c.id == categoryId).firstOrNull;
    final selSource = findPriceSourceInCatalog(priceSourceId, catalog);
    final sourceLabel = selSource?.label ?? (priceSourceId.isNotEmpty ? '$priceSourceId (نامعتبر)' : null);
    return SubPage(
      title: 'مدیریت دارایی‌ها',
      body: ListView(controller: _scroll, padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
        AppCard(
          key: ValueKey('form$formKey'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(editingId != null ? 'ویرایش دارایی' : 'تعریف دارایی جدید', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white))),
              if (editingId != null) TextButton.icon(onPressed: _reset, icon: const Icon(Icons.close, size: 14), label: const Text('انصراف')),
            ]),
            const SizedBox(height: 12),
            IconPickerField(value: iconUrl, onChanged: (u) => setState(() => iconUrl = u), userId: user.id, folder: 'assets', fallback: Icons.show_chart, label: 'آیکون (اختیاری)'),
            const SizedBox(height: 14),
            Row(children: [
              const Expanded(child: FieldLabel('دسته‌بندی (اختیاری)')),
              TextButton(onPressed: () => Nav.push(context, '/manage/categories'), child: const Text('مدیریت دسته‌ها', style: TextStyle(fontSize: 11, color: C.purple400))),
            ]),
            SelectBox(
              text: selCat?.name ?? 'بدون دسته',
              placeholder: selCat == null,
              leading: selCat != null ? Dot(hexColor(selCat.color)) : const Icon(Icons.folder_outlined, size: 15, color: C.slate500),
              trailing: Icons.chevron_left,
              onTap: () async {
                final r = await showCategoryPicker(context, title: 'انتخاب دسته‌بندی دارایی', kind: 'asset', categories: s.categories, value: categoryId.isEmpty ? null : categoryId, allowNone: true, noneLabel: 'بدون دسته');
                if (r != null) setState(() => categoryId = r == kNone ? '' : r);
              },
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: Field(label: 'نام دارایی', child: AppTextField(value: name, onChanged: (v) => name = v, hint: 'مثلا: طلا'))),
              const SizedBox(width: 10),
              Expanded(child: Field(label: 'واحد', child: AppTextField(value: unit, onChanged: (v) => unit = v, hint: 'مثلا: گرم'))),
            ]),
            const FieldLabel('منبع قیمت (اختیاری)'),
            SelectBox(
              text: sourceLabel ?? 'دستی (بدون منبع)',
              placeholder: sourceLabel == null,
              leading: Icon(Icons.link, size: 15, color: selSource != null ? C.purple300 : (priceSourceId.isNotEmpty ? C.amber300 : C.slate500)),
              trailing: Icons.chevron_left,
              onTap: () async {
                final items = [
                  for (final src in catalog.where((x) => !x.deprecated)) PickItem(id: src.slug, label: src.label, sublabel: src.slug, leading: const Icon(Icons.link, size: 14, color: C.slate500)),
                  if (priceSourceId.isNotEmpty && selSource == null)
                    PickItem(id: priceSourceId, label: priceSourceId, sublabel: 'نامعتبر — ممکن است از کاتالوگ حذف شده باشد', leading: const Icon(Icons.link, size: 14, color: C.amber300)),
                ];
                final r = await showListPicker(context,
                    title: 'انتخاب منبع قیمت', items: items, value: priceSourceId.isEmpty ? null : priceSourceId, allowNone: true, noneLabel: 'دستی (بدون منبع)', emptyLabel: 'منبع قیمتی پیکربندی نشده.');
                if (r != null) setState(() => priceSourceId = r == kNone ? '' : r);
              },
            ),
            const SizedBox(height: 10),
            InkWell(
              onTap: () => setState(() => showAdvanced = !showAdvanced),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(children: [
                  const Expanded(child: Text('تنظیمات پیشرفته', style: TextStyle(fontSize: 13, color: C.slate300))),
                  Icon(showAdvanced ? Icons.expand_less : Icons.expand_more, size: 18, color: C.slate400),
                ]),
              ),
            ),
            if (showAdvanced) ...[
              Field(
                label: 'تعداد اعشار نمایش مقدار',
                hint: 'فقط نمایش UI را کنترل می‌کند.',
                child: Row(children: [
                  IconBtn(Icons.remove, onTap: decimalPlaces > 0 ? () => setState(() => decimalPlaces--) : null),
                  Expanded(child: Text('$decimalPlaces', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white))),
                  IconBtn(Icons.add, onTap: decimalPlaces < 12 ? () => setState(() => decimalPlaces++) : null),
                ]),
              ),
              SwitchRow(title: 'شامل در ارزش کل سبد', subtitle: 'خاموش: در جمع داشبورد لحاظ نمی‌شود', value: includeBalance, onChanged: (v) => setState(() => includeBalance = v)),
              SwitchRow(title: 'شامل در سود/زیان', subtitle: 'خاموش: در گزارش سود/زیان لحاظ نمی‌شود', value: includePnl, onChanged: (v) => setState(() => includePnl = v)),
            ],
            const SizedBox(height: 10),
            AppButton(submitting ? 'در حال ثبت...' : (editingId != null ? 'ثبت تغییرات' : 'ذخیره دارایی'),
                variant: editingId != null ? BtnVariant.primary : BtnVariant.secondary, expand: true, onPressed: submitting ? null : () => _submit(s)),
          ]),
        ),
        const SizedBox(height: 18),
        const Text('دارایی‌های تعریف شده', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: C.slate300)),
        const SizedBox(height: 10),
        if (s.assets.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('هیچ دارایی ثبت نشده.', textAlign: TextAlign.center, style: TextStyle(color: C.slate500, fontSize: 12))),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderStart: (_) => haptic('light'),
          onReorder: (from, to) {
            haptic();
            final list = [...s.assets];
            if (to > from) to -= 1;
            list.insert(to, list.removeAt(from));
            final ordered = [for (var i = 0; i < list.length; i++) list[i].copyWith(orderIndex: i)];
            s.update((st) => st.assets = ordered);
            _persistOrder(s, ordered);
          },
          children: [
            for (var i = 0; i < s.assets.length; i++)
              Builder(
                key: ValueKey(s.assets[i].id),
                builder: (_) {
                  final a = s.assets[i];
                  final cat = s.categories.where((c) => c.id == a.categoryId).firstOrNull;
                  final color = hexColor(cat?.color ?? '#64748b');
                  final src = findPriceSourceInCatalog(a.priceSourceId, catalog);
                  final isPending = pending.contains(a.id);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Opacity(
                      opacity: isPending ? 0.6 : 1,
                      child: AppCard(
                        padding: const EdgeInsets.all(12),
                        borderColor: editingId == a.id ? C.purple500.withValues(alpha: 0.5) : null,
                        child: Row(children: [
                          ReorderableDragStartListener(index: i, child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.drag_indicator, size: 18, color: C.slate500))),
                          const SizedBox(width: 6),
                          EntityIcon(iconUrl: a.iconUrl, fallback: Icons.show_chart, bgColor: color.withValues(alpha: 0.13), color: color, size: 38),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(a.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.slate200)),
                              Text('${cat?.name ?? 'بدون دسته'} • ${a.unit}', style: const TextStyle(fontSize: 11, color: C.slate500)),
                              Wrap(spacing: 4, children: [
                                if (a.includeInBalance == false) _tag('خارج از ارزش کل سبد', C.amber300),
                                if (!a.includeInProfitLoss) _tag('خارج از سود/زیان', C.slate400),
                                if (src != null) _tag(src.label, C.purple300),
                              ]),
                            ]),
                          ),
                          IconButton(icon: const Icon(Icons.edit_outlined, size: 17, color: C.slate400), onPressed: isPending ? null : () => _edit(a)),
                          IconButton(icon: const Icon(Icons.delete_outline, size: 17, color: C.rose300), onPressed: isPending ? null : () => _delete(s, a.id)),
                        ]),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ]),
    );
  }

  Widget _tag(String t, Color c) => Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
        child: Text(t, style: TextStyle(fontSize: 9, color: c)),
      );
}
