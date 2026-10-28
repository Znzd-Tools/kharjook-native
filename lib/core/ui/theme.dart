import 'package:flutter/material.dart';

class C {
  static const background = Color(0xFF0F1015);
  static const shell = Color(0xFF161722);
  static const raised = Color(0xFF1A1B26);
  static const hover = Color(0xFF222436);
  static const inset = Color(0xFF0F1015);
  static const purple = Color(0xFF9333EA);
  static const purple400 = Color(0xFFC084FC);
  static const purple300 = Color(0xFFD8B4FE);
  static const purple500 = Color(0xFFA855F7);
  static const violet = Color(0xFF8B5CF6);
  static const cyan = Color(0xFF06B6D4);
  static const cyan300 = Color(0xFF67E8F9);
  static const emerald = Color(0xFF10B981);
  static const emerald300 = Color(0xFF6EE7B7);
  static const emerald400 = Color(0xFF34D399);
  static const rose = Color(0xFFF43F5E);
  static const rose300 = Color(0xFFFDA4AF);
  static const rose400 = Color(0xFFFB7185);
  static const amber = Color(0xFFF59E0B);
  static const amber300 = Color(0xFFFCD34D);
  static const sky400 = Color(0xFF38BDF8);
  static const slate200 = Color(0xFFE2E8F0);
  static const slate300 = Color(0xFFCBD5E1);
  static const slate400 = Color(0xFF94A3B8);
  static const slate500 = Color(0xFF64748B);
  static const slate600 = Color(0xFF475569);
  static const border = Color(0x14FFFFFF); // white/8
  static const borderSoft = Color(0x0DFFFFFF); // white/5
  static const white5 = Color(0x0DFFFFFF);
  static const white10 = Color(0x1AFFFFFF);

  static Color pnl(num v) => v > 0 ? emerald400 : (v < 0 ? rose400 : slate300);
}

ThemeData buildTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    fontFamily: 'IRANSansX',
    scaffoldBackgroundColor: C.shell,
    colorScheme: const ColorScheme.dark(
      primary: C.purple,
      secondary: C.purple400,
      surface: C.raised,
      error: C.rose400,
    ),
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: C.slate200, displayColor: Colors.white, fontFamily: 'IRANSansX'),
    appBarTheme: const AppBarTheme(
      backgroundColor: C.raised,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: 'IRANSansX', fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
    ),
    dividerColor: C.borderSoft,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.raised,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: const TextStyle(color: C.slate500, fontSize: 13),
      labelStyle: const TextStyle(color: C.slate400, fontSize: 13),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.white10)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.white10)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.purple500)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : C.slate400),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? C.purple : C.hover),
    ),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: C.shell, showDragHandle: true, dragHandleColor: C.slate600),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: Colors.transparent, elevation: 0),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: C.purple500),
  );
}
