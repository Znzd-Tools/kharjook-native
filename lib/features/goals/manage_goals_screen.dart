// Port of ManageGoalsView.tsx.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/logic/domain_utils.dart';
import '../../core/models.dart';
import '../../core/store.dart';
import '../../core/ui/category_picker.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/toast.dart';
import '../../core/ui/widgets.dart';
import '../../core/utils/digits.dart';
import '../transactions/tx_logic.dart';
import 'goal_progress_display.dart';

double _positive(String v) {
  final x = n(v);
  return x.isFinite && x > 0 ? x : 0;
}

class _CategoryBudgetRow {
  final String categoryId, categoryName;
  final double? parentTarget;
  final double childrenSum;
  _CategoryBudgetRow(this.categoryId, this.categoryName, this.parentTarget, this.childrenSum);
}

class ManageGoalsScreen extends StatefulWidget {
  const ManageGoalsScreen({super.key});
  @override
  State<ManageGoalsScreen> createState() => _ManageGoalsScreenState();
}

class _ManageGoalsScreenState extends State<ManageGoalsScreen> {
  String? editingId;
  String scope = 'asset', assetId = '', categoryId = '', targetKind = 'allocation_percent', targetValue = '';
  bool submitting = false;
  int formKey = 0;
  final Set<String> pending = {};

  void _reset() => setState(() {
        editingId = null;
        scope = 'asset';
        assetId = categoryId = targetValue = '';
        targetKind = 'allocation_percent';
        formKey++;
      });

  void _switchScope(String s) => setState(() {
        editingId = null;
        scope = s;
        assetId = categoryId = targetValue = '';
        targetKind = 'allocation_percent';
        formKey++;
      });

  String get _effectiveKind => scope == 'asset_group' ? 'allocation_percent' : targetKind;

  Json _payload(String userId) {
    final t = _positive(targetValue);
    final k = _effectiveKind;
    return {
      'user_id': userId,
      'scope': scope,
      'asset_id': scope == 'asset' ? assetId : null,
      'category_id': scope == 'asset_group' ? categoryId : null,
      'target_kind': k,
      'target_quantity': k == 'quantity' ? t : null,
      'target_percent': k == 'allocation_percent' ? t : null,
    };
  }

  Goal _goalFrom(String id, Json p, String? createdAt) => Goal(
        id: id,
        userId: p['user_id'] as String,
        scope: p['scope'] as String,
        assetId: p['asset_id'] as String?,
        categoryId: p['category_id'] as String?,
        targetKind: p['target_kind'] as String,
        targetQuantity: p['target_quantity'] as double?,
        targetPercent: p['target_percent'] as double?,
        createdAt: createdAt,
      );

  Future<void> _submit(PortfolioStore s, bool blocking, List<String> issues) async {
    final user = s.user;
    if (user == null) return;
    if (blocking) {
      Toast.error(issues.isNotEmpty ? issues.first : 'ترکیب هدف‌ها معتبر نیست.');
      return;
    }
    final kind = _effectiveKind;
    final dup = s.goals.any((g) {
      if (g.id == editingId) return false;
      if (g.scope != scope || g.targetKind != kind) return false;
      return scope == 'asset' ? g.assetId == assetId : g.categoryId == categoryId;
    });
    if (dup) {
      Toast.error('برای این مورد قبلا هدفی با همین نوع ثبت شده است.');
      return;
    }
    final payload = _payload(user.id);
    final editing = editingId;
    Future<void> execute() async {
      final snapshot = s.goals;
      final c = Supabase.instance.client;
      if (editing != null) {
        final old = snapshot.where((g) => g.id == editing).firstOrNull;
        setState(() => pending.add(editing));
        s.update((st) => st.goals = [for (final g in st.goals) g.id == editing ? _goalFrom(editing, payload, old?.createdAt) : g]);
        try {
          final data = await c.from('goals').update(payload).eq('id', editing).select().single();
          final saved = Goal.fromJson(data);
          s.update((st) => st.goals = [for (final g in st.goals) g.id == editing ? saved : g]);
        } catch (e) {
          s.update((st) => st.goals = snapshot);
          rethrow;
        } finally {
          if (mounted) setState(() => pending.remove(editing));
        }
      } else {
        final tempId = 'temp-goal-${const Uuid().v4()}';
        setState(() => pending.add(tempId));
        s.update((st) => st.goals = [...st.goals, _goalFrom(tempId, payload, DateTime.now().toUtc().toIso8601String())]);
        try {
          final data = await c.from('goals').insert([payload]).select().single();
          final saved = Goal.fromJson(data);
          s.update((st) => st.goals = [for (final g in st.goals) g.id == tempId ? saved : g]);
        } catch (e) {
          s.update((st) => st.goals = snapshot);
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
      Toast.error('ذخیره هدف ناموفق بود.', actionLabel: 'تلاش مجدد', onAction: () => execute().catchError((_) => Toast.error('ذخیره هدف ناموفق بود.')));
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<void> _delete(PortfolioStore s, Goal g) async {
    if (s.user == null) return;
    if (!await confirmDialog(context, message: 'این هدف حذف شود؟', danger: true, confirmLabel: 'حذف')) return;
    Future<void> execute() async {
      final snapshot = s.goals;
      setState(() => pending.add(g.id));
      s.update((st) => st.goals = st.goals.where((x) => x.id != g.id).toList());
      try {
        await Supabase.instance.client.from('goals').delete().eq('id', g.id);
      } catch (e) {
        s.update((st) => st.goals = snapshot);
        rethrow;
      } finally {
        if (mounted) setState(() => pending.remove(g.id));
      }
      if (editingId == g.id) _reset();
    }

    try {
      await execute();
    } catch (_) {
      Toast.error('حذف هدف ناموفق بود.', actionLabel: 'تلاش مجدد', onAction: () => execute().catchError((_) => Toast.error('حذف هدف ناموفق بود.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<PortfolioStore>();
    final user = s.user;
    if (user == null) return const SizedBox.shrink();
    final assetById = {for (final a in s.assets) a.id: a};
    final catById = {for (final c in s.categories.where((c) => c.kind == 'asset')) c.id: c};
    final snapshots = buildAssetSnapshots(s.assets, s.transactions, s.currencyMode, s.usdRate);
    final totalValue = totalSnapshotValueToman(snapshots);
    final sortedGoals = [...s.goals]..sort((a, b) {
        if (a.scope != b.scope) return a.scope == 'asset_group' ? -1 : 1;
        return (a.createdAt ?? '').compareTo(b.createdAt ?? '');
      });

    final kind = _effectiveKind;
    final target = _positive(targetValue);
    final percentInvalid = kind == 'allocation_percent' && (target <= 0 || target > 100);
    final quantityInvalid = kind == 'quantity' && target <= 0;
    final targetInvalid = percentInvalid || quantityInvalid;
    final targetMissing = scope == 'asset' ? assetId.isEmpty : categoryId.isEmpty;

    // Budget validation (live, with the draft form included).
    final next = s.goals.where((g) => g.id != editingId).toList();
    if (!targetMissing && !targetInvalid && kind == 'allocation_percent') {
      next.add(Goal(
        id: editingId ?? '__draft__',
        userId: user.id,
        scope: scope,
        assetId: scope == 'asset' ? assetId : null,
        categoryId: scope == 'asset_group' ? categoryId : null,
        targetKind: 'allocation_percent',
        targetPercent: target,
      ));
    }
    final parents = next.where((g) => g.scope == 'asset_group' && g.targetKind == 'allocation_percent');
    final children = next.where((g) => g.scope == 'asset' && g.targetKind == 'allocation_percent');
    final parentSum = parents.fold<double>(0, (a, g) => a + (g.targetPercent ?? 0));
    final childSum = children.fold<double>(0, (a, g) => a + (g.targetPercent ?? 0));
    final childByCat = <String, double>{};
    for (final g in children) {
      final cid = g.assetId != null ? assetById[g.assetId]?.categoryId : null;
      if (cid == null) continue;
      childByCat[cid] = (childByCat[cid] ?? 0) + (g.targetPercent ?? 0);
    }
    final parentByCat = <String, double>{for (final g in parents) if (g.categoryId != null) g.categoryId!: g.targetPercent ?? 0};
    final issues = <String>[
      if (parentSum > 100.0001) 'جمع درصد هدف‌های گروهی ${parentSum.toStringAsFixed(1)}% است و نباید از 100% بیشتر شود.',
      if (childSum > 100.0001) 'جمع درصد هدف‌های دارایی ${childSum.toStringAsFixed(1)}% است و نباید از 100% بیشتر شود.',
      for (final e in childByCat.entries)
        if (parentByCat[e.key] != null && e.value > parentByCat[e.key]! + 0.0001)
          'در گروه «${catById[e.key]?.name ?? 'گروه'}»، مجموع درصد فرزندها ${e.value.toStringAsFixed(1)}% از هدف گروه (${parentByCat[e.key]!.toStringAsFixed(1)}%) بیشتر است.',
    ];
    final catRows = [
      for (final id in {...childByCat.keys, ...parentByCat.keys}) _CategoryBudgetRow(id, catById[id]?.name ?? 'گروه', parentByCat[id], childByCat[id] ?? 0),
    ]..sort((a, b) => ((b.parentTarget ?? -1) - (a.parentTarget ?? -1)).sign.toInt());
    final blocking = issues.isNotEmpty;
    final canSubmit = !submitting && !targetMissing && !targetInvalid && !blocking;
    final selAsset = assetId.isEmpty ? null : assetById[assetId];
    final selCat = categoryId.isEmpty ? null : catById[categoryId];

    Widget kindBtn(String k, IconData icon, String label) => Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => targetKind = k),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: targetKind == k ? C.purple500.withValues(alpha: 0.1) : C.inset,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: targetKind == k ? C.purple500.withValues(alpha: 0.4) : C.white10),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 15, color: targetKind == k ? C.purple300 : C.slate400),
                const SizedBox(width: 6),
                Text(label, style: TextStyle(fontSize: 13, color: targetKind == k ? C.purple300 : C.slate400)),
              ]),
            ),
          ),
        );

    Widget bar(double fraction, bool danger) => ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: Container(
            height: 6,
            color: C.white10,
            alignment: AlignmentDirectional.centerStart,
            child: FractionallySizedBox(
              widthFactor: fraction.clamp(0, 1).toDouble(),
              child: Container(
                decoration: BoxDecoration(
                  color: danger ? C.rose400 : null,
                  gradient: danger ? null : const LinearGradient(colors: [C.purple500, Color(0xFF22D3EE)]),
                ),
              ),
            ),
          ),
        );

    Widget budgetRow(String label, double used) {
      final danger = used > 100;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 12, color: C.slate400))),
            Text('${used.toStringAsFixed(1)}% used / ${math.max(0, 100 - used).toStringAsFixed(1)}% free',
                textDirection: TextDirection.ltr, style: TextStyle(fontSize: 11, color: danger ? C.rose300 : C.slate300)),
          ]),
          const SizedBox(height: 4),
          bar(used / 100, danger),
        ]),
      );
    }

    return SubPage(
      title: 'هدف‌ها',
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
        AppCard(
          key: ValueKey(formKey),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Icon(Icons.track_changes, size: 18, color: C.purple400),
              const SizedBox(width: 6),
              Expanded(child: Text(editingId != null ? 'ویرایش هدف' : 'هدف جدید', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white))),
              if (editingId != null) TextButton.icon(onPressed: _reset, icon: const Icon(Icons.close, size: 14), label: const Text('لغو')),
            ]),
            const SizedBox(height: 10),
            Segmented<String>(options: const [('asset', 'دارایی'), ('asset_group', 'گروه دارایی')], value: scope, onChanged: _switchScope),
            const SizedBox(height: 12),
            if (scope == 'asset')
              Field(
                label: 'دارایی',
                child: SelectBox(
                  text: selAsset?.name ?? 'انتخاب دارایی',
                  placeholder: selAsset == null,
                  leading: const Icon(Icons.show_chart, size: 16, color: C.slate400),
                  onTap: () async {
                    final r = await showListPicker(context,
                        title: 'انتخاب دارایی',
                        items: [for (final a in s.assets) PickItem(id: a.id, label: a.name, sublabel: a.unit, leading: const Icon(Icons.show_chart, size: 14, color: C.slate400))],
                        value: assetId.isEmpty ? null : assetId);
                    if (r != null && r != kNone) setState(() => assetId = r);
                  },
                ),
              )
            else
              Field(
                label: 'گروه دارایی',
                child: SelectBox(
                  text: selCat?.name ?? 'انتخاب گروه',
                  placeholder: selCat == null,
                  leading: const Icon(Icons.folder_outlined, size: 16, color: C.slate400),
                  onTap: () async {
                    final r = await showCategoryPicker(context, title: 'انتخاب گروه دارایی', kind: 'asset', categories: s.categories, value: categoryId.isEmpty ? null : categoryId);
                    if (r != null && r != kNone) setState(() => categoryId = r);
                  },
                ),
              ),
            if (scope == 'asset') ...[
              Row(children: [kindBtn('allocation_percent', Icons.percent, 'درصد از سبد'), const SizedBox(width: 8), kindBtn('quantity', Icons.show_chart, 'تعداد/مقدار')]),
              const SizedBox(height: 12),
            ],
            Field(
              label: kind == 'quantity' ? 'هدف مقداری' : 'هدف درصدی',
              hint: percentInvalid && targetValue.isNotEmpty ? 'درصد باید بین ۰ و ۱۰۰ باشد.' : null,
              child: NumberInput(value: targetValue, hint: kind == 'quantity' ? 'مثلا 2.5' : 'مثلا 25', suffix: kind == 'allocation_percent' ? '%' : null, onChanged: (v) => setState(() => targetValue = v)),
            ),
            if (issues.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: C.rose.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.rose.withValues(alpha: 0.3))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final i in issues) Text(i, style: const TextStyle(fontSize: 11, color: C.rose300, height: 1.6))]),
              ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: C.inset, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.white10)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('خلاصه بودجه درصدی', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: C.slate200)),
                const Text('محاسبه زنده با پیش‌نمایش فرم فعلی', style: TextStyle(fontSize: 10, color: C.slate500)),
                budgetRow('مجموع هدف‌های گروهی', parentSum),
                budgetRow('مجموع هدف‌های دارایی', childSum),
                if (catRows.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  const Text('نسبت فرزندها به والد هر گروه', style: TextStyle(fontSize: 11, color: C.slate400)),
                  for (final r in catRows.take(6))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Row(children: [
                          Expanded(child: Text(r.categoryName, style: const TextStyle(fontSize: 11, color: C.slate300))),
                          if (r.parentTarget == null)
                            const Text('والد ندارد', style: TextStyle(fontSize: 10, color: C.slate500))
                          else
                            Text('${r.childrenSum.toStringAsFixed(1)} / ${r.parentTarget!.toStringAsFixed(1)}%',
                                textDirection: TextDirection.ltr, style: TextStyle(fontSize: 10, color: r.childrenSum > r.parentTarget! ? C.rose300 : C.slate400)),
                        ]),
                        if (r.parentTarget != null) ...[
                          const SizedBox(height: 3),
                          bar(r.parentTarget! > 0 ? r.childrenSum / r.parentTarget! : 0, r.childrenSum > r.parentTarget!),
                        ],
                      ]),
                    ),
                ],
              ]),
            ),
            const SizedBox(height: 12),
            AppButton(submitting ? 'در حال ذخیره...' : (editingId != null ? 'ذخیره تغییرات' : 'افزودن هدف'), expand: true, onPressed: canSubmit ? () => _submit(s, blocking, issues) : null),
          ]),
        ),
        const SizedBox(height: 16),
        Row(children: [
          const Expanded(child: Text('هدف‌های فعال', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white))),
          Text(toPersianDigits(s.goals.length), style: const TextStyle(fontSize: 12, color: C.slate400)),
        ]),
        const SizedBox(height: 10),
        if (sortedGoals.isEmpty)
          const Padding(padding: EdgeInsets.all(20), child: Text('هنوز هدفی ثبت نشده است.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: C.slate500)))
        else
          for (final g in sortedGoals)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Opacity(
                opacity: pending.contains(g.id) ? 0.6 : 1,
                child: AppCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Icon(g.scope == 'asset' ? Icons.show_chart : Icons.folder_outlined, size: 15, color: C.purple400),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(
                            g.scope == 'asset' ? (assetById[g.assetId]?.name ?? 'دارایی حذف‌شده') : (catById[g.categoryId]?.name ?? 'گروه حذف‌شده'),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.slate200),
                          ),
                          Text(g.targetKind == 'quantity' ? 'هدف مقداری' : 'هدف درصدی', style: const TextStyle(fontSize: 10, color: C.slate500)),
                        ]),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 16, color: C.slate400),
                        onPressed: () => setState(() {
                          editingId = g.id;
                          scope = g.scope;
                          assetId = g.assetId ?? '';
                          categoryId = g.categoryId ?? '';
                          targetKind = g.targetKind;
                          targetValue = jsNumStr(g.targetQuantity ?? g.targetPercent);
                          formKey++;
                        }),
                      ),
                      IconButton(icon: const Icon(Icons.delete_outline, size: 16, color: C.rose300), onPressed: () => _delete(s, g)),
                    ]),
                    const SizedBox(height: 8),
                    GoalProgressDisplay(
                      label: '',
                      kind: goalValueKindFromGoal(g.targetKind),
                      unit: g.assetId != null ? (assetById[g.assetId]?.unit ?? '') : '',
                      progress: g.scope == 'asset' ? calculateAssetGoalProgress(g, snapshots, totalValue) : calculateGroupGoalProgress(g, snapshots, totalValue),
                    ),
                  ]),
                ),
              ),
            ),
      ]),
    );
  }
}
