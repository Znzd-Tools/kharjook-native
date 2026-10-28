import 'package:flutter/material.dart';

import 'theme.dart';

final rootMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Port of Toast.tsx — success / error / info with optional action.
class Toast {
  static void success(String m, {String? actionLabel, VoidCallback? onAction, int? durationMs}) =>
      _show(m, C.emerald400, Icons.check_circle_outline, actionLabel, onAction, durationMs ?? 4000);
  static void error(String m, {String? actionLabel, VoidCallback? onAction, int? durationMs}) =>
      _show(m, C.rose400, Icons.error_outline, actionLabel, onAction, durationMs ?? 6000);
  static void info(String m, {String? actionLabel, VoidCallback? onAction, int? durationMs}) =>
      _show(m, C.sky400, Icons.info_outline, actionLabel, onAction, durationMs ?? 4000);

  static void _show(String message, Color accent, IconData icon, String? actionLabel, VoidCallback? onAction, int ms) {
    final m = rootMessengerKey.currentState;
    if (m == null) return;
    late final ScaffoldFeatureController<SnackBar, SnackBarClosedReason> ctrl;
    ctrl = m.showSnackBar(SnackBar(
      duration: Duration(milliseconds: ms <= 0 ? 86400000 : ms),
      padding: EdgeInsets.zero,
      content: Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Color.alphaBlend(accent.withValues(alpha: 0.12), C.raised),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withValues(alpha: 0.35)),
          ),
          child: Row(children: [
            Icon(icon, color: accent, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: const TextStyle(color: Color(0xFFF1F5F9), fontSize: 13, height: 1.6, fontFamily: 'IRANSansX'))),
            if (actionLabel != null)
              TextButton(
                onPressed: () {
                  onAction?.call();
                  ctrl.close();
                },
                child: Text(actionLabel, style: TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            InkWell(onTap: () => ctrl.close(), child: const Icon(Icons.close, size: 14, color: C.slate400)),
          ]),
        ),
      ),
    ));
  }
}
