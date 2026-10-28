// Port of GoalProgressDisplay.tsx.

import 'package:flutter/material.dart';

import '../../core/logic/domain_utils.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/widgets.dart';

class GoalProgressDisplay extends StatelessWidget {
  final String label;
  final GoalProgress? progress;
  final String kind;
  final String unit;
  final bool compact;
  const GoalProgressDisplay({super.key, required this.label, required this.progress, required this.kind, this.unit = '', this.compact = false});

  @override
  Widget build(BuildContext context) {
    final valueUnit = kind == 'percent' ? '%' : unit;
    final delta = computeGoalDelta(progress, kind, valueUnit);
    final bar = computeGoalBarMetricsForKind(progress, kind);
    final (badgeBg, badgeFg) = switch (delta.status) {
      'met' || 'over' => (C.emerald400.withValues(alpha: 0.1), C.emerald300),
      _ => delta.label == '—' ? (C.white5, C.slate500) : (C.amber.withValues(alpha: 0.1), C.amber300),
    };
    final grad = delta.status == 'under' ? const [C.purple500, Color(0xFF22D3EE)] : const [C.emerald, Color(0xFF2DD4BF)];
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(999)),
      child: Money(delta.label, style: TextStyle(fontSize: compact ? 9 : 10, fontWeight: FontWeight.w700, color: badgeFg)),
    );
    final barW = _GoalBar(bar: bar, colors: grad, height: compact ? 6 : 10);
    if (compact) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          const Icon(Icons.track_changes, size: 10, color: C.slate500),
          const SizedBox(width: 3),
          Expanded(child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: C.slate400))),
          badge,
        ]),
        const SizedBox(height: 4),
        barW,
      ]);
    }
    Widget cell(String l, String v) => Expanded(
          child: Column(children: [
            Text(l, style: const TextStyle(fontSize: 10, color: C.slate500)),
            Money(v, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: C.slate200)),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        if (label.isNotEmpty) ...[
          const Icon(Icons.track_changes, size: 12, color: C.slate400),
          const SizedBox(width: 4),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12, color: C.slate300))),
        ] else
          const Spacer(),
        badge,
      ]),
      const SizedBox(height: 8),
      barW,
      const SizedBox(height: 8),
      Directionality(
        textDirection: TextDirection.ltr,
        child: Row(children: [
          cell('فعلی', formatGoalValue(progress?.current ?? 0, kind, valueUnit)),
          cell('هدف', formatGoalValue(progress?.target ?? 0, kind, valueUnit)),
          cell('فاصله', goalGapLabel(progress, kind, valueUnit)),
        ]),
      ),
    ]);
  }
}

class _GoalBar extends StatelessWidget {
  final GoalBarMetrics bar;
  final List<Color> colors;
  final double height;
  const _GoalBar({required this.bar, required this.colors, required this.height});
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (_, c) {
        final w = c.maxWidth;
        return Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            height: height + 8,
            child: Stack(alignment: Alignment.centerLeft, children: [
              Container(height: height, decoration: BoxDecoration(color: C.white5, borderRadius: BorderRadius.circular(999))),
              Container(
                width: w * bar.baseFillPct.clamp(0, 100) / 100,
                height: height,
                decoration: BoxDecoration(gradient: LinearGradient(colors: colors), borderRadius: BorderRadius.circular(999)),
              ),
              if (bar.showOverflow && bar.overflowPct > 0)
                Positioned(
                  left: w * bar.targetPct / 100,
                  child: Container(
                    width: w * bar.overflowPct.clamp(0, 100) / 100,
                    height: height,
                    decoration: BoxDecoration(color: C.amber.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(999)),
                  ),
                ),
              if (bar.targetPct > 0 && bar.targetPct < 100)
                Positioned(
                  left: w * bar.targetPct / 100 - 1,
                  child: Container(width: 2, height: height + 8, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2))),
                ),
            ]),
          ),
        );
      });
}
