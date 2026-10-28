import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/digits.dart';
import '../utils/format.dart';
import '../utils/jalali.dart';
import 'theme.dart';

void haptic([String intent = 'selection']) {
  switch (intent) {
    case 'light':
      HapticFeedback.lightImpact();
    case 'medium':
      HapticFeedback.mediumImpact();
    case 'success':
    case 'error':
      HapticFeedback.heavyImpact();
    default:
      HapticFeedback.selectionClick();
  }
}

Color hexColor(String? hex, [Color fallback = C.slate400]) {
  if (hex == null) return fallback;
  var h = hex.replaceAll('#', '').trim();
  if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
  if (h.length != 6) return fallback;
  final v = int.tryParse(h, radix: 16);
  return v == null ? fallback : Color(0xFF000000 | v);
}

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  final double radius;
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.color, this.borderColor, this.radius = 20});

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? C.raised,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? C.borderSoft),
      ),
      child: child,
    );
    if (onTap == null) return box;
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: BorderRadius.circular(radius), onTap: onTap, child: box),
    );
  }
}

enum BtnVariant { primary, secondary, danger, ghost }

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final BtnVariant variant;
  final IconData? icon;
  final bool loading;
  final bool expand;
  final bool dense;
  const AppButton(this.label,
      {super.key, this.onPressed, this.variant = BtnVariant.primary, this.icon, this.loading = false, this.expand = false, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (variant) {
      BtnVariant.primary => (C.purple, Colors.white, Colors.transparent),
      BtnVariant.secondary => (C.white5, C.slate200, C.white10),
      BtnVariant.danger => (const Color(0x33E11D48), C.rose300, const Color(0x4DF43F5E)),
      BtnVariant.ghost => (Colors.transparent, C.slate300, Colors.transparent),
    };
    final disabled = onPressed == null || loading;
    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
        else if (icon != null)
          Icon(icon, size: 16, color: fg),
        if ((loading || icon != null) && label.isNotEmpty) const SizedBox(width: 6),
        if (label.isNotEmpty)
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: dense ? 12 : 14))),
      ],
    );
    return Opacity(
      opacity: disabled && !loading ? 0.5 : 1,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: disabled ? null : onPressed,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: dense ? 12 : 16, vertical: dense ? 8 : 13),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
            child: child,
          ),
        ),
      ),
    );
  }
}

class IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final Color? color;
  final double size;
  const IconBtn(this.icon, {super.key, this.onTap, this.tooltip, this.color, this.size = 18});
  @override
  Widget build(BuildContext context) {
    final w = Material(
      color: C.white5,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: C.white10)),
          child: Icon(icon, size: size, color: onTap == null ? C.slate600 : (color ?? C.slate300)),
        ),
      ),
    );
    return tooltip == null ? w : Tooltip(message: tooltip!, child: w);
  }
}

class FilterChipX extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;
  final String label;
  final Color? activeColor;
  const FilterChipX({super.key, required this.active, required this.onTap, required this.label, this.activeColor});
  @override
  Widget build(BuildContext context) {
    final ac = activeColor ?? C.purple400;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () {
        haptic();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? ac.withValues(alpha: 0.18) : C.raised,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? ac.withValues(alpha: 0.45) : C.white10),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: active ? ac : C.slate400)),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData? icon;
  final String title;
  final String? description;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;
  const EmptyState({super.key, this.icon, required this.title, this.description, this.actionLabel, this.onAction, this.secondaryActionLabel, this.onSecondaryAction});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
      child: Column(children: [
        if (icon != null)
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: C.white5, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.white10)),
            child: Icon(icon, color: C.slate500),
          ),
        const SizedBox(height: 14),
        Text(title, textAlign: TextAlign.center, style: const TextStyle(color: C.slate400, fontSize: 13, fontWeight: FontWeight.w500)),
        if (description != null) ...[
          const SizedBox(height: 6),
          Text(description!, textAlign: TextAlign.center, style: const TextStyle(color: C.slate600, fontSize: 12, height: 1.6)),
        ],
        if (actionLabel != null && onAction != null)
          TextButton(onPressed: onAction, child: Text(actionLabel!, style: const TextStyle(color: C.purple400, fontWeight: FontWeight.w600))),
        if (secondaryActionLabel != null && onSecondaryAction != null)
          TextButton(onPressed: onSecondaryAction, child: Text(secondaryActionLabel!, style: const TextStyle(color: C.slate500, fontSize: 12))),
      ]),
    );
  }
}

class FieldLabel extends StatelessWidget {
  final String text;
  const FieldLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6, right: 2),
        child: Text(text, style: const TextStyle(fontSize: 12, color: C.slate400)),
      );
}

class Field extends StatelessWidget {
  final String label;
  final Widget child;
  final String? hint;
  const Field({super.key, required this.label, required this.child, this.hint});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FieldLabel(label),
          child,
          if (hint != null)
            Padding(padding: const EdgeInsets.only(top: 5, right: 2), child: Text(hint!, style: const TextStyle(fontSize: 11, color: C.slate500, height: 1.5))),
        ]),
      );
}

/// Plain text input bound to a value (keeps controller in sync).
class TextInput extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;
  final bool ltr;
  final bool obscure;
  final int maxLines;
  final TextInputType? keyboardType;
  final bool autofocus;
  final Widget? prefixIcon;
  final List<TextInputFormatter>? formatters;
  final bool enabled;
  const TextInput({
    super.key,
    required this.value,
    required this.onChanged,
    this.hint,
    this.ltr = false,
    this.obscure = false,
    this.maxLines = 1,
    this.keyboardType,
    this.autofocus = false,
    this.prefixIcon,
    this.formatters,
    this.enabled = true,
  });
  @override
  State<TextInput> createState() => _TextInputState();
}

class _TextInputState extends State<TextInput> {
  late final TextEditingController _c = TextEditingController(text: widget.value);
  @override
  void didUpdateWidget(covariant TextInput old) {
    super.didUpdateWidget(old);
    if (widget.value != _c.text) _c.text = widget.value;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _c,
        enabled: widget.enabled,
        onChanged: widget.onChanged,
        obscureText: widget.obscure,
        maxLines: widget.obscure ? 1 : widget.maxLines,
        minLines: 1,
        autofocus: widget.autofocus,
        keyboardType: widget.keyboardType,
        inputFormatters: widget.formatters,
        textDirection: widget.ltr ? TextDirection.ltr : null,
        textAlign: widget.ltr ? TextAlign.left : TextAlign.start,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(hintText: widget.hint, prefixIcon: widget.prefixIcon),
      );
}

/// Port of FormattedNumberInput: canonical value (ASCII digits + one `.`),
/// grouped display, Persian digits accepted.
class NumberInput extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;
  final String? suffix;
  final bool autofocus;
  final bool enabled;
  const NumberInput({super.key, required this.value, required this.onChanged, this.hint, this.suffix, this.autofocus = false, this.enabled = true});
  @override
  State<NumberInput> createState() => _NumberInputState();
}

class _NumberInputState extends State<NumberInput> {
  late final TextEditingController _c = TextEditingController(text: formatCanonicalNumberDisplay(widget.value));

  @override
  void didUpdateWidget(covariant NumberInput old) {
    super.didUpdateWidget(old);
    final display = formatCanonicalNumberDisplay(widget.value);
    if (parseFormattedNumberToCanonical(_c.text) != widget.value) {
      _c.value = TextEditingValue(text: display, selection: TextSelection.collapsed(offset: display.length));
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  bool _isCanon(String ch) => ch == '.' || (ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57);

  void _onChanged(String raw) {
    final sel = _c.selection.baseOffset < 0 ? raw.length : _c.selection.baseOffset;
    final latin = latinizeDigits(raw);
    var before = 0;
    for (var i = 0; i < sel && i < latin.length; i++) {
      if (_isCanon(latin[i])) before++;
    }
    final canonical = parseFormattedNumberToCanonical(raw);
    final display = formatCanonicalNumberDisplay(canonical);
    var pos = display.length;
    if (before <= 0) {
      pos = 0;
    } else {
      var seen = 0;
      for (var i = 0; i < display.length; i++) {
        if (_isCanon(display[i])) {
          seen++;
          if (seen == before) {
            pos = i + 1;
            break;
          }
        }
      }
    }
    _c.value = TextEditingValue(text: display, selection: TextSelection.collapsed(offset: pos));
    widget.onChanged(canonical);
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _c,
        enabled: widget.enabled,
        autofocus: widget.autofocus,
        onChanged: _onChanged,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.left,
        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          hintText: widget.hint ?? '0',
          hintTextDirection: TextDirection.ltr,
          suffixText: widget.suffix,
          suffixStyle: const TextStyle(color: C.slate500, fontSize: 12),
        ),
      );
}

/// Tappable "select" row used by sheet pickers and the date field.
class SelectBox extends StatelessWidget {
  final String text;
  final bool placeholder;
  final VoidCallback? onTap;
  final Widget? leading;
  final IconData trailing;
  const SelectBox({super.key, required this.text, this.placeholder = false, this.onTap, this.leading, this.trailing = Icons.expand_more});
  @override
  Widget build(BuildContext context) => Material(
        color: C.raised,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap == null
              ? null
              : () {
                  haptic();
                  onTap!();
                },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: C.white10)),
            child: Row(children: [
              if (leading != null) ...[leading!, const SizedBox(width: 10)],
              Expanded(
                child: Text(text,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: placeholder ? C.slate500 : Colors.white)),
              ),
              Icon(trailing, size: 18, color: C.slate500),
            ]),
          ),
        ),
      );
}

class DateField extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final String placeholder;
  const DateField({super.key, required this.value, required this.onChanged, this.placeholder = 'انتخاب تاریخ'});
  @override
  Widget build(BuildContext context) {
    final p = parseJalaali(value);
    return SelectBox(
      text: p == null ? placeholder : '${formatJalaaliHuman(p)}  ·  ${kWeekdayNames[jalaaliWeekday(p)]}',
      placeholder: p == null,
      trailing: Icons.calendar_today_outlined,
      onTap: () async {
        final r = await showJalaliDatePicker(context, value);
        if (r != null) onChanged(r);
      },
    );
  }
}

Future<T?> showAppSheet<T>(BuildContext context, {String? title, required Widget Function(BuildContext) builder, bool scrollable = true}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.88),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            Flexible(
              child: scrollable
                  ? SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), child: builder(ctx))
                  : Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), child: builder(ctx)),
            ),
          ]),
        ),
      ),
    ),
  );
}

Future<bool> confirmDialog(
  BuildContext context, {
  String title = 'تأیید',
  required String message,
  String confirmLabel = 'تأیید',
  String cancelLabel = 'انصراف',
  bool danger = false,
}) async {
  final r = await showAppSheet<bool>(
    context,
    title: title,
    builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(message, style: const TextStyle(fontSize: 13, color: C.slate300, height: 1.7)),
      const SizedBox(height: 22),
      Row(children: [
        Expanded(child: AppButton(cancelLabel, variant: BtnVariant.secondary, expand: true, onPressed: () => Navigator.pop(ctx, false))),
        const SizedBox(width: 12),
        Expanded(
          child: AppButton(confirmLabel,
              variant: danger ? BtnVariant.danger : BtnVariant.primary, expand: true, onPressed: () => Navigator.pop(ctx, true)),
        ),
      ]),
    ]),
  );
  return r ?? false;
}

// ─── Jalali date picker (IOSDatePicker port) ────────────────────────────────

Future<String?> showJalaliDatePicker(BuildContext context, String value, {int? minYear, int? maxYear}) {
  final today = todayJalaali();
  final init = parseJalaali(value) ?? today;
  return showAppSheet<String>(
    context,
    title: 'انتخاب تاریخ',
    scrollable: false,
    builder: (ctx) => _JalaliPicker(initial: init, minYear: minYear ?? today.jy - 15, maxYear: maxYear ?? today.jy + 2),
  );
}

class _JalaliPicker extends StatefulWidget {
  final JDate initial;
  final int minYear, maxYear;
  const _JalaliPicker({required this.initial, required this.minYear, required this.maxYear});
  @override
  State<_JalaliPicker> createState() => _JalaliPickerState();
}

class _JalaliPickerState extends State<_JalaliPicker> {
  late JDate draft = widget.initial;
  late FixedExtentScrollController _d, _m, _y;
  final _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    _build();
  }

  void _build() {
    _d = FixedExtentScrollController(initialItem: draft.jd - 1);
    _m = FixedExtentScrollController(initialItem: draft.jm - 1);
    _y = FixedExtentScrollController(initialItem: (draft.jy - widget.minYear).clamp(0, widget.maxYear - widget.minYear));
  }

  JDate get effective {
    final len = jalaaliMonthLength(draft.jy, draft.jm);
    return draft.jd > len ? draft.copyWith(jd: len) : draft;
  }

  Widget _wheel(FixedExtentScrollController c, int count, String Function(int) label, int selected, ValueChanged<int> onSel, int flex) {
    return Expanded(
      flex: flex,
      child: ListWheelScrollView.useDelegate(
        controller: c,
        itemExtent: 40,
        physics: const FixedExtentScrollPhysics(),
        perspective: 0.003,
        onSelectedItemChanged: (i) {
          haptic();
          onSel(i);
        },
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: count,
          builder: (_, i) => Center(
            child: Text(label(i),
                style: TextStyle(fontSize: 14, color: i == selected ? Colors.white : C.slate500, fontWeight: i == selected ? FontWeight.w700 : FontWeight.w400)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = effective;
    final len = jalaaliMonthLength(e.jy, e.jm);
    return Column(key: _key, mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        height: 200,
        child: Stack(children: [
          Positioned.fill(
            child: Center(
              child: Container(height: 40, margin: const EdgeInsets.symmetric(horizontal: 8), decoration: BoxDecoration(color: C.white5, borderRadius: BorderRadius.circular(12))),
            ),
          ),
          Row(children: [
            _wheel(_d, len, (i) => toPersianDigits(i + 1), e.jd - 1, (i) => setState(() => draft = draft.copyWith(jd: i + 1)), 10),
            _wheel(_m, 12, (i) => kJalaliMonths[i], e.jm - 1, (i) => setState(() => draft = draft.copyWith(jm: i + 1)), 14),
            _wheel(_y, widget.maxYear - widget.minYear + 1, (i) => toPersianDigits(widget.minYear + i), e.jy - widget.minYear,
                (i) => setState(() => draft = draft.copyWith(jy: widget.minYear + i)), 10),
          ]),
        ]),
      ),
      const SizedBox(height: 18),
      Row(children: [
        AppButton('امروز', variant: BtnVariant.secondary, dense: true, onPressed: () {
          final t = todayJalaali();
          setState(() => draft = t);
          _d.jumpToItem(t.jd - 1);
          _m.jumpToItem(t.jm - 1);
          _y.jumpToItem(t.jy - widget.minYear);
        }),
        const Spacer(),
        AppButton('انصراف', variant: BtnVariant.secondary, dense: true, onPressed: () => Navigator.pop(context)),
        const SizedBox(width: 8),
        AppButton('تایید', dense: true, onPressed: () => Navigator.pop(context, formatJalaali(effective))),
      ]),
    ]);
  }
}

// ─── Sheet pickers ──────────────────────────────────────────────────────────

class PickItem {
  final String id;
  final String label;
  final String? sublabel;
  final Widget? leading;
  final Widget? trailing;
  final bool disabled;
  const PickItem({required this.id, required this.label, this.sublabel, this.leading, this.trailing, this.disabled = false});
}

const kNone = '__none__';

/// Port of ListSheetPicker. Returns selected id, [kNone] for the none row, or null on dismiss.
Future<String?> showListPicker(
  BuildContext context, {
  required String title,
  required List<PickItem> items,
  String? value,
  bool allowNone = false,
  String noneLabel = '— بدون انتخاب —',
  bool searchable = true,
  String emptyLabel = 'موردی یافت نشد.',
}) {
  return showAppSheet<String>(context, title: title, scrollable: false, builder: (ctx) {
    return _ListPickerBody(items: items, value: value, allowNone: allowNone, noneLabel: noneLabel, searchable: searchable, emptyLabel: emptyLabel);
  });
}

class _ListPickerBody extends StatefulWidget {
  final List<PickItem> items;
  final String? value;
  final bool allowNone;
  final String noneLabel;
  final bool searchable;
  final String emptyLabel;
  const _ListPickerBody({required this.items, this.value, required this.allowNone, required this.noneLabel, required this.searchable, required this.emptyLabel});
  @override
  State<_ListPickerBody> createState() => _ListPickerBodyState();
}

class _ListPickerBodyState extends State<_ListPickerBody> {
  String q = '';
  @override
  Widget build(BuildContext context) {
    final query = q.trim().toLowerCase();
    final filtered = query.isEmpty
        ? widget.items
        : widget.items.where((i) => i.label.toLowerCase().contains(query) || (i.sublabel?.toLowerCase().contains(query) ?? false)).toList();
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (widget.searchable)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextInput(value: q, onChanged: (v) => setState(() => q = v), hint: 'جستجو...', prefixIcon: const Icon(Icons.search, size: 18, color: C.slate500)),
        ),
      Flexible(
        child: ListView(shrinkWrap: true, children: [
          if (widget.allowNone)
            PickRow(label: widget.noneLabel, selected: widget.value == null, leading: const Icon(Icons.block, size: 15, color: C.slate500), onTap: () => Navigator.pop(context, kNone)),
          if (filtered.isEmpty)
            Padding(padding: const EdgeInsets.symmetric(vertical: 30), child: Text(widget.emptyLabel, textAlign: TextAlign.center, style: const TextStyle(color: C.slate500, fontSize: 12)))
          else
            for (final it in filtered)
              PickRow(
                label: it.label,
                sublabel: it.sublabel,
                leading: it.leading,
                trailing: it.trailing,
                selected: widget.value == it.id,
                disabled: it.disabled,
                onTap: () {
                  haptic();
                  Navigator.pop(context, it.id);
                },
              ),
        ]),
      ),
    ]);
  }
}

class PickRow extends StatelessWidget {
  final String label;
  final String? sublabel;
  final Widget? leading;
  final Widget? trailing;
  final bool selected;
  final bool disabled;
  final VoidCallback? onTap;
  final double indent;
  const PickRow({super.key, required this.label, this.sublabel, this.leading, this.trailing, this.selected = false, this.disabled = false, this.onTap, this.indent = 0});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsetsDirectional.only(bottom: 6, start: indent),
      child: Opacity(
        opacity: disabled ? 0.4 : 1,
        child: Material(
          color: selected ? C.purple500.withValues(alpha: 0.1) : C.raised,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: disabled ? null : onTap,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: selected ? C.purple500.withValues(alpha: 0.4) : C.borderSoft),
              ),
              child: Row(children: [
                if (leading != null) ...[leading!, const SizedBox(width: 10)],
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: selected ? Colors.white : C.slate200, fontWeight: selected ? FontWeight.w700 : FontWeight.w400)),
                    if (sublabel != null)
                      Padding(padding: const EdgeInsets.only(top: 2), child: Text(sublabel!, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: C.slate500))),
                  ]),
                ),
                if (trailing != null) trailing!,
                if (selected) const Padding(padding: EdgeInsetsDirectional.only(start: 6), child: Icon(Icons.check, size: 15, color: C.purple300)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class Dot extends StatelessWidget {
  final Color color;
  final double size;
  const Dot(this.color, {super.key, this.size = 10});
  @override
  Widget build(BuildContext context) => Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

/// Circular avatar: uploaded icon or fallback glyph (EntityIcon.tsx).
class EntityIcon extends StatelessWidget {
  final String? iconUrl;
  final IconData fallback;
  final Color? bgColor;
  final Color? color;
  final double size;
  const EntityIcon({super.key, this.iconUrl, required this.fallback, this.bgColor, this.color, this.size = 40});
  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(size * 0.3);
    if (iconUrl != null && iconUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: r,
        child: Container(
          width: size,
          height: size,
          color: C.white5,
          child: Image.network(iconUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(fallback, size: size * 0.5, color: color ?? C.slate400)),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bgColor ?? const Color(0x1F94A3B8), borderRadius: r),
      child: Icon(fallback, size: size * 0.5, color: color ?? C.slate400),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final IconData? icon;
  const SectionTitle(this.title, {super.key, this.subtitle, this.trailing, this.icon});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          if (icon != null) ...[Icon(icon, size: 16, color: C.purple400), const SizedBox(width: 6)],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
              if (subtitle != null) Text(subtitle!, style: const TextStyle(fontSize: 11, color: C.slate500)),
            ]),
          ),
          if (trailing != null) trailing!,
        ]),
      );
}

/// LTR money text (amounts are always shown left-to-right).
class Money extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? align;
  const Money(this.text, {super.key, this.style, this.align});
  @override
  Widget build(BuildContext context) => Text(text,
      textDirection: TextDirection.ltr,
      textAlign: align,
      overflow: TextOverflow.ellipsis,
      style: style ?? const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white));
}

class SwitchRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  const SwitchRow({super.key, required this.title, this.subtitle, required this.value, this.onChanged});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 13, color: C.slate200)),
              if (subtitle != null) Text(subtitle!, style: const TextStyle(fontSize: 11, color: C.slate500, height: 1.5)),
            ]),
          ),
          Switch(value: value, onChanged: onChanged),
        ]),
      );
}

class Segmented<T> extends StatelessWidget {
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  const Segmented({super.key, required this.options, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: C.raised, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.white10)),
        child: Row(children: [
          for (final (v, label) in options)
            Expanded(
              child: GestureDetector(
                onTap: () {
                  haptic();
                  onChanged(v);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(color: v == value ? C.purple : Colors.transparent, borderRadius: BorderRadius.circular(9)),
                  child: Text(label,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: v == value ? Colors.white : C.slate400)),
                ),
              ),
            ),
        ]),
      );
}

/// Scaffold for pushed (non-tab) pages: title + back.
class SubPage extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? fab;
  final Widget? bottom;
  const SubPage({super.key, required this.title, required this.body, this.actions, this.fab, this.bottom});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: C.inset,
        appBar: AppBar(
          title: Text(title),
          backgroundColor: C.inset,
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.maybePop(context)),
          actions: [...?actions, const SizedBox(width: 8)],
        ),
        floatingActionButton: fab,
        bottomNavigationBar: bottom,
        body: SafeArea(top: false, child: body),
      );
}

class StatPill extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const StatPill({super.key, required this.label, required this.value, this.color});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: C.white5, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.borderSoft)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 11, color: C.slate500)),
          const SizedBox(height: 4),
          Money(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color ?? Colors.white)),
        ]),
      );
}
