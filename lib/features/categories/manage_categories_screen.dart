// Port of ManageCategoriesView.tsx (tree, sibling reorder, expense caps).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/models.dart';
import '../../core/store.dart';
import '../../core/ui/category_picker.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/toast.dart';
import '../../core/ui/widgets.dart';
import '../../core/utils/format.dart';
import '../transactions/tx_logic.dart';

const kCategoryColorsList = ['#8b5cf6', '#3b82f6', '#10b981', '#f59e0b', '#ef4444', '#ec4899', '#6366f1', '#14b8a6'];

const _deletePrompts = {
  'asset': 'مطمئنی؟ با پاک کردن دسته، دارایی‌های مرتبط بی‌دسته میشن.',
  'income': 'مطمئنی؟ با پاک کردن دسته، تراکنش‌های مرتبط بی‌دسته میشن.',
  'expense': 'مطمئنی؟ با پاک کردن دسته، تراکنش‌های مرتبط بی‌دسته میشن.',
};

class ManageCategoriesScreen extends StatefulWidget {
  const ManageCategoriesScreen({super.key});
  @override
  State<ManageCategoriesScreen> createState() => _ManageCategoriesScreenState();
}

class _ManageCategoriesScreenState extends State<ManageCategoriesScreen> {
  String kind = 'asset';
  String? editingId, parentId;
  String name = '', color = kCategoryColorsList.first, cap = '';
  int formKey = 0;
  bool submitting = false;
  final Set<String> pending = {};
  Map<String, CategorySpendingCap> caps = {};

  SupabaseClient get _c => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadCaps();
  }

  Future<void> _loadCaps() async {
    try {
      final data = await _c.from('category_spending_caps').select();
      if (!mounted) return;
      setState(() => caps = {for (final c in (data as List).cast<Json>().map(CategorySpendingCap.fromJson)) c.categoryId: c});
    } catch (_) {}
  }

  void _reset() => setState(() {
        editingId = parentId = null;
        name = cap = '';
        color = kCategoryColorsList.first;
        formKey++;
      });

  void _switchTab(String k) {
    if (k == kind) return;
    kind = k;
    _reset();
  }

  Set<String> _descendants(List<Category> scoped, String? rootId) {
    final acc = <String>{};
    if (rootId == null) return acc;
    final stack = [rootId];
    while (stack.isNotEmpty) {
      final id = stack.removeLast();
      for (final c in scoped.where((c) => c.parentId == id)) {
        if (acc.add(c.id)) stack.add(c.id);
      }
    }
    return acc;
  }

  Future<void> _persistCap(String userId, String categoryId, String raw) async {
    final t = raw.trim();
    if (t.isEmpty) {
      await _c.from('category_spending_caps').delete().eq('category_id', categoryId);
      setState(() => caps.remove(categoryId));
      return;
    }
    final limit = n(t);
    if (!limit.isFinite || limit <= 0) throw Exception('سقف ماهانه نامعتبر است.');
    final data = await _c
        .from('category_spending_caps')
        .upsert({'user_id': userId, 'category_id': categoryId, 'monthly_limit_toman': limit, 'updated_at': DateTime.now().toUtc().toIso8601String()}, onConflict: 'user_id,category_id')
        .select()
        .single();
    setState(() => caps[categoryId] = CategorySpendingCap.fromJson(data));
  }

  Future<void> _submit(PortfolioStore s) async {
    final user = s.user;
    if (user == null) return;
    final nm = name.trim();
    if (nm.isEmpty) {
      Toast.error('نام دسته الزامی است.');
      return;
    }
    final scoped = s.categories.where((c) => c.kind == kind).toList();
    final pid = kind == 'asset' ? null : parentId;
    final editing = editingId;
    if (pid != null && editing != null && _descendants(scoped, editing).contains(pid)) {
      Toast.error('نمی‌توان والدی انتخاب کرد که خودش زیرمجموعه‌ی این دسته است.');
      return;
    }
    final clr = color, capRaw = cap, k = kind;

    Future<void> execute() async {
      final snapshot = s.categories;
      if (editing != null) {
        final patch = {'name': nm, 'color': clr, 'parent_id': pid};
        setState(() => pending.add(editing));
        s.update((st) => st.categories = [for (final c in st.categories) c.id == editing ? c.copyWith(name: nm, color: clr, parentId: pid, clearParent: pid == null) : c]);
        try {
          final data = await _c.from('categories').update(patch).eq('id', editing).select().single();
          final saved = Category.fromJson(data);
          s.update((st) => st.categories = [for (final c in st.categories) c.id == editing ? saved : c]);
        } catch (e) {
          s.update((st) => st.categories = snapshot);
          rethrow;
        } finally {
          if (mounted) setState(() => pending.remove(editing));
        }
        if (k == 'expense') await _persistCap(user.id, editing, capRaw);
      } else {
        final nextOrder = scoped.where((c) => c.parentId == pid).fold<int>(-1, (m, c) => c.orderIndex != null && c.orderIndex! > m ? c.orderIndex! : m) + 1;
        final tempId = 'temp-category-${const Uuid().v4()}';
        setState(() => pending.add(tempId));
        s.update((st) => st.categories = [
              ...st.categories,
              Category(id: tempId, userId: user.id, name: nm, color: clr, kind: k, parentId: pid, orderIndex: nextOrder, createdAt: DateTime.now().toUtc().toIso8601String()),
            ]);
        String? savedId;
        try {
          final data = await _c.from('categories').insert([
            {'user_id': user.id, 'name': nm, 'color': clr, 'kind': k, 'parent_id': pid, 'order_index': nextOrder},
          ]).select().single();
          final saved = Category.fromJson(data);
          savedId = saved.id;
          s.update((st) => st.categories = [for (final c in st.categories) c.id == tempId ? saved : c]);
        } catch (e) {
          s.update((st) => st.categories = snapshot);
          rethrow;
        } finally {
          if (mounted) setState(() => pending.remove(tempId));
        }
        if (k == 'expense' && capRaw.trim().isNotEmpty) await _persistCap(user.id, savedId, capRaw);
      }
      _reset();
    }

    setState(() => submitting = true);
    try {
      await execute();
    } catch (_) {
      Toast.error('خطا در ثبت دسته‌بندی.', actionLabel: 'تلاش مجدد', onAction: () => execute().catchError((_) => Toast.error('خطا در ثبت دسته‌بندی.')));
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<void> _delete(PortfolioStore s, Category cat) async {
    if (!await confirmDialog(context, message: _deletePrompts[cat.kind] ?? _deletePrompts['expense']!, danger: true, confirmLabel: 'حذف')) return;
    Future<void> execute() async {
      final snapshot = s.categories;
      setState(() => pending.add(cat.id));
      // DB sets parent_id → null on direct children; mirror that locally.
      s.update((st) => st.categories = [
            for (final c in st.categories)
              if (c.id != cat.id) c.parentId == cat.id ? c.copyWith(clearParent: true) : c,
          ]);
      try {
        await _c.from('categories').delete().eq('id', cat.id);
      } catch (e) {
        s.update((st) => st.categories = snapshot);
        rethrow;
      } finally {
        if (mounted) setState(() => pending.remove(cat.id));
      }
      if (editingId == cat.id) _reset();
    }

    try {
      await execute();
    } catch (_) {
      Toast.error('خطا در حذف.', actionLabel: 'تلاش مجدد', onAction: () => execute().catchError((_) => Toast.error('خطا در حذف.')));
    }
  }

  Future<void> _reorder(PortfolioStore s, List<Category> siblings, int from, int to) async {
    haptic();
    final list = [...siblings];
    if (to > from) to -= 1;
    if (from == to) return;
    list.insert(to, list.removeAt(from));
    final order = {for (var i = 0; i < list.length; i++) list[i].id: i};
    s.update((st) => st.categories = [for (final c in st.categories) order.containsKey(c.id) ? c.copyWith(orderIndex: order[c.id]) : c]);
    try {
      await Future.wait([for (var i = 0; i < list.length; i++) _c.from('categories').update({'order_index': i}).eq('id', list[i].id)]);
    } catch (_) {
      Toast.error('ذخیره ترتیب دسته‌ها ناموفق بود.');
      try {
        final data = await _c.from('categories').select().order('order_index', ascending: true, nullsFirst: false).order('created_at', ascending: true);
        s.update((st) => st.categories = (data as List).cast<Json>().map(Category.fromJson).toList());
      } catch (_) {}
    }
  }

  Widget _siblings(PortfolioStore s, List<Category> items, Map<String, List<Category>> childrenOf, int depth) {
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      onReorderStart: (_) => haptic('light'),
      onReorder: (from, to) => _reorder(s, items, from, to),
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            key: ValueKey(items[i].id),
            padding: EdgeInsetsDirectional.only(bottom: 6, start: depth > 0 ? 14 : 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Opacity(
                opacity: pending.contains(items[i].id) ? 0.6 : 1,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: depth > 0 ? 4 : 8),
                  decoration: BoxDecoration(
                    color: depth > 0 ? C.white5 : C.raised,
                    borderRadius: BorderRadius.circular(depth > 0 ? 12 : 16),
                    border: Border.all(color: editingId == items[i].id ? C.purple500 : C.borderSoft),
                  ),
                  child: Row(children: [
                    ReorderableDragStartListener(index: i, child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.drag_indicator, size: depth > 0 ? 14 : 16, color: C.slate500))),
                    const SizedBox(width: 4),
                    Dot(hexColor(items[i].color), size: depth > 0 ? 8 : 12),
                    const SizedBox(width: 10),
                    Expanded(child: Text(items[i].name, style: TextStyle(fontSize: depth > 0 ? 12 : 14, color: depth > 0 ? C.slate300 : C.slate200, fontWeight: depth > 0 ? FontWeight.w400 : FontWeight.w500))),
                    if ((caps[items[i].id]?.monthlyLimitToman ?? 0) > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: C.amber.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                        child: Text('سقف ${formatEnNumber(caps[items[i].id]!.monthlyLimitToman, maxFrac: 3)}', style: const TextStyle(fontSize: 10, color: C.amber300)),
                      ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.edit_outlined, size: depth > 0 ? 16 : 18, color: C.slate400),
                      onPressed: pending.contains(items[i].id)
                          ? null
                          : () => setState(() {
                                final c = items[i];
                                editingId = c.id;
                                name = c.name;
                                color = c.color;
                                parentId = c.parentId;
                                cap = caps[c.id] != null ? jsNumStr(caps[c.id]!.monthlyLimitToman) : '';
                                formKey++;
                              }),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.delete_outline, size: depth > 0 ? 16 : 18, color: C.rose300),
                      onPressed: pending.contains(items[i].id) ? null : () => _delete(s, items[i]),
                    ),
                  ]),
                ),
              ),
              if ((childrenOf[items[i].id] ?? const []).isNotEmpty) ...[
                const SizedBox(height: 6),
                _siblings(s, childrenOf[items[i].id]!, childrenOf, depth + 1),
              ],
            ]),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<PortfolioStore>();
    if (s.user == null) return const SizedBox.shrink();
    final scoped = s.categories.where((c) => c.kind == kind).toList();
    final ids = scoped.map((c) => c.id).toSet();
    final roots = <Category>[];
    final childrenOf = <String, List<Category>>{};
    for (final c in scoped) {
      if (c.parentId != null && ids.contains(c.parentId)) {
        (childrenOf[c.parentId!] ??= []).add(c);
      } else {
        roots.add(c);
      }
    }
    final exclude = {..._descendants(scoped, editingId), ?editingId};
    final parent = parentId == null ? null : s.categories.where((c) => c.id == parentId).firstOrNull;
    final hint = kind == 'asset' ? 'نام دسته (مثلا: خودرو)' : (kind == 'income' ? 'نام دسته (مثلا: حقوق)' : 'نام دسته (مثلا: خوراک)');

    return SubPage(
      title: 'مدیریت دسته‌بندی‌ها',
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
        Segmented<String>(options: const [('asset', 'دارایی'), ('income', 'درآمد'), ('expense', 'هزینه')], value: kind, onChanged: _switchTab),
        const SizedBox(height: 14),
        AppCard(
          key: ValueKey('form$formKey'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(editingId != null ? 'ویرایش دسته' : 'دسته جدید', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.purple400))),
              if (editingId != null) TextButton.icon(onPressed: _reset, icon: const Icon(Icons.close, size: 14), label: const Text('انصراف')),
            ]),
            const SizedBox(height: 8),
            Field(label: 'نام دسته', child: AppTextField(value: name, hint: hint, onChanged: (v) => name = v.length > 64 ? v.substring(0, 64) : v)),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final c in kCategoryColorsList)
                GestureDetector(
                  onTap: () => setState(() => color = c),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: hexColor(c), shape: BoxShape.circle, border: Border.all(color: color == c ? Colors.white : Colors.transparent, width: 2)),
                    child: color == c ? const Icon(Icons.check, size: 18, color: Colors.white) : null,
                  ),
                ),
            ]),
            const SizedBox(height: 14),
            if (kind != 'asset')
              Field(
                label: 'زیرمجموعه‌ی (اختیاری)',
                child: SelectBox(
                  text: parent?.name ?? 'بدون والد (دسته اصلی)',
                  placeholder: parent == null,
                  leading: parent != null ? Dot(hexColor(parent.color)) : const Icon(Icons.folder_outlined, size: 14, color: C.slate400),
                  trailing: Icons.chevron_left,
                  onTap: () async {
                    final r = await showCategoryPicker(context,
                        title: 'انتخاب دستهٔ والد', kind: kind, categories: s.categories, value: parentId, allowNone: true, noneLabel: 'بدون والد (دسته اصلی)', excludeIds: exclude);
                    if (r != null) setState(() => parentId = r == kNone ? null : r);
                  },
                ),
              ),
            if (kind == 'expense')
              Field(
                label: 'سقف هزینه ماهانه (تومان، اختیاری)',
                hint: 'هزینه زیرمجموعه‌ها هم در محاسبه لحاظ می‌شود.',
                child: NumberInput(value: cap, hint: 'مثلا ۵,۰۰۰,۰۰۰', onChanged: (v) => cap = v),
              ),
            AppButton(
              submitting ? 'در حال ثبت...' : (editingId != null ? 'ثبت تغییرات' : 'افزودن دسته'),
              variant: editingId != null ? BtnVariant.primary : BtnVariant.secondary,
              expand: true,
              onPressed: submitting ? null : () => _submit(s),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        if (roots.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('هیچ دسته‌بندی ثبت نشده.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: C.slate500))),
        _siblings(s, roots, childrenOf, 0),
      ]),
    );
  }
}
