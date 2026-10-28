// Port of CategorySheetPicker.tsx — tree picker with search + expand.

import 'package:flutter/material.dart';

import '../models.dart';
import 'theme.dart';
import 'widgets.dart';

/// Returns category id, [kNone] for "none", or null on dismiss.
Future<String?> showCategoryPicker(
  BuildContext context, {
  required String title,
  required String kind,
  required List<Category> categories,
  String? value,
  bool allowNone = false,
  String noneLabel = '— بدون انتخاب —',
  Set<String> excludeIds = const {},
}) {
  return showAppSheet<String>(
    context,
    title: title,
    scrollable: false,
    builder: (_) => _CategoryPickerBody(
      scoped: categories.where((c) => c.kind == kind).toList(),
      value: value,
      allowNone: allowNone,
      noneLabel: noneLabel,
      excludeIds: excludeIds,
    ),
  );
}

class _Flat {
  final Category c;
  final int depth;
  _Flat(this.c, this.depth);
}

class _CategoryPickerBody extends StatefulWidget {
  final List<Category> scoped;
  final String? value;
  final bool allowNone;
  final String noneLabel;
  final Set<String> excludeIds;
  const _CategoryPickerBody({required this.scoped, this.value, required this.allowNone, required this.noneLabel, required this.excludeIds});
  @override
  State<_CategoryPickerBody> createState() => _CategoryPickerBodyState();
}

class _CategoryPickerBodyState extends State<_CategoryPickerBody> {
  String q = '';
  Set<String> expanded = {};
  late final Map<String?, List<Category>> byParent;
  late final Map<String, Category> byId;

  @override
  void initState() {
    super.initState();
    final scoped = widget.scoped;
    byId = {for (final c in scoped) c.id: c};
    final excluded = <String>{};
    void mark(String id) {
      if (!excluded.add(id)) return;
      for (final c in scoped) {
        if (c.parentId == id) mark(c.id);
      }
    }

    widget.excludeIds.forEach(mark);
    byParent = {};
    for (final c in scoped) {
      if (excluded.contains(c.id)) continue;
      byParent.putIfAbsent(c.parentId, () => []).add(c);
    }
    final visible = <String>{for (final l in byParent.values) ...l.map((c) => c.id)};
    for (final c in scoped) {
      if (!visible.contains(c.id)) continue;
      if (c.parentId != null && !visible.contains(c.parentId)) {
        final root = byParent.putIfAbsent(null, () => []);
        if (!root.any((x) => x.id == c.id)) root.add(c);
      }
    }
    // Auto-expand the path to the current value.
    var cursor = widget.value == null ? null : byId[widget.value];
    while (cursor?.parentId != null) {
      expanded.add(cursor!.parentId!);
      cursor = byId[cursor.parentId];
    }
  }

  List<_Flat> _flatten() {
    final out = <_Flat>[];
    final bp = <String?, List<Category>>{};
    for (final c in widget.scoped) {
      bp.putIfAbsent(c.parentId, () => []).add(c);
    }
    void visit(String? pid, int depth) {
      for (final n in bp[pid] ?? const <Category>[]) {
        if (widget.excludeIds.contains(n.id)) continue;
        out.add(_Flat(n, depth));
        visit(n.id, depth + 1);
      }
    }

    visit(null, 0);
    final ids = widget.scoped.map((c) => c.id).toSet();
    for (final c in widget.scoped) {
      if (widget.excludeIds.contains(c.id)) continue;
      if (c.parentId == null || ids.contains(c.parentId)) continue;
      if (out.any((o) => o.c.id == c.id)) continue;
      out.add(_Flat(c, 0));
    }
    final query = q.trim().toLowerCase();
    if (query.isEmpty) return out;
    return out.where((f) => f.c.name.toLowerCase().contains(query)).toList();
  }

  void _commit(String id) {
    haptic();
    Navigator.pop(context, id);
  }

  List<Widget> _tree(String? parentId, int depth) {
    final out = <Widget>[];
    for (final node in byParent[parentId] ?? const <Category>[]) {
      final kids = byParent[node.id] ?? const [];
      final isOpen = expanded.contains(node.id);
      out.add(Row(children: [
        SizedBox(width: depth * 16.0),
        if (kids.isNotEmpty)
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(isOpen ? Icons.expand_more : Icons.chevron_left, size: 18, color: C.slate400),
            onPressed: () => setState(() => isOpen ? expanded.remove(node.id) : expanded.add(node.id)),
          )
        else
          const SizedBox(width: 40),
        Expanded(
          child: PickRow(
            label: node.name,
            selected: widget.value == node.id,
            leading: Row(mainAxisSize: MainAxisSize.min, children: [
              Dot(hexColor(node.color)),
              const SizedBox(width: 6),
              Icon(Icons.folder_outlined, size: 15, color: widget.value == node.id ? C.purple300 : C.slate500),
            ]),
            onTap: () => _commit(node.id),
          ),
        ),
      ]));
      if (kids.isNotEmpty && isOpen) out.addAll(_tree(node.id, depth + 1));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final searching = q.trim().isNotEmpty;
    final items = searching ? _flatten() : const <_Flat>[];
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextInput(value: q, onChanged: (v) => setState(() => q = v), hint: 'جستجو...', prefixIcon: const Icon(Icons.search, size: 18, color: C.slate500)),
      ),
      Flexible(
        child: ListView(shrinkWrap: true, children: [
          if (widget.allowNone)
            PickRow(
              label: widget.noneLabel,
              selected: widget.value == null,
              leading: const Icon(Icons.block, size: 15, color: C.slate500),
              onTap: () => Navigator.pop(context, kNone),
            ),
          if (searching && items.isEmpty && !widget.allowNone)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Text('دسته‌ای یافت نشد.', textAlign: TextAlign.center, style: TextStyle(color: C.slate500, fontSize: 12)),
            ),
          if (searching)
            for (final it in items)
              PickRow(
                label: it.c.name,
                indent: it.depth * 18.0,
                selected: widget.value == it.c.id,
                leading: Row(mainAxisSize: MainAxisSize.min, children: [Dot(hexColor(it.c.color)), const SizedBox(width: 6), const Icon(Icons.folder_outlined, size: 15, color: C.slate500)]),
                onTap: () => _commit(it.c.id),
              )
          else
            ..._tree(null, 0),
        ]),
      ),
    ]);
  }
}

/// "a › b › c" path label for a category.
String categoryPath(String? id, List<Category> categories) {
  if (id == null) return '';
  final byId = {for (final c in categories) c.id: c};
  final names = <String>[];
  var cur = byId[id];
  final seen = <String>{};
  while (cur != null && seen.add(cur.id)) {
    names.insert(0, cur.name);
    cur = cur.parentId == null ? null : byId[cur.parentId];
  }
  return names.join(' › ');
}
