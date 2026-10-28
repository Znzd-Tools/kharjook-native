// Port of Shell.tsx / BottomNav.tsx / MoreHubSheet.tsx.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/store.dart';
import '../core/ui/theme.dart';
import '../core/ui/widgets.dart';
import '../features/assets/assets_tab.dart';
import '../features/dashboard/home_tab.dart';
import '../features/deadlines/deadlines_tab.dart';
import '../features/wallets/wallets_tab.dart';
import 'router.dart';

final shellTab = ValueNotifier<int>(0);

class Shell extends StatelessWidget {
  const Shell({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (shellTab.value != 0) {
          shellTab.value = 0;
        } else {
          Navigator.of(context).maybePop();
        }
      },
      child: Scaffold(
        backgroundColor: C.shell,
        body: Column(children: [
          const AppHeader(),
          Expanded(
            child: ValueListenableBuilder<int>(
              valueListenable: shellTab,
              builder: (_, tab, __) => IndexedStack(index: tab, children: const [HomeTab(), AssetsTab(), WalletsTab(), DeadlinesTab()]),
            ),
          ),
        ]),
        bottomNavigationBar: const BottomNav(),
      ),
    );
  }
}

class AppHeader extends StatelessWidget {
  const AppHeader({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<PortfolioStore>();
    return Container(
      color: C.raised,
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 10, 20, 12),
      child: Row(children: [
        GestureDetector(
          onTap: () => Nav.push(context, '/'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ShaderMask(
              shaderCallback: (r) => const LinearGradient(colors: [C.purple400, C.purple]).createShader(r),
              child: const Text('خرجوک', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
            const Text('مدیریت دارایی', style: TextStyle(fontSize: 10, color: C.slate500, letterSpacing: 2)),
          ]),
        ),
        const Spacer(),
        GestureDetector(
          onTap: () {
            haptic();
            s.toggleCurrency();
          },
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: C.hover, borderRadius: BorderRadius.circular(999), border: Border.all(color: C.purple500.withValues(alpha: 0.2))),
            child: Row(children: [
              _pill('تومان', s.currencyMode == 'TOMAN'),
              _pill('دلار', s.currencyMode == 'USD'),
            ]),
          ),
        ),
        const SizedBox(width: 8),
        IconBtn(Icons.grid_view_rounded, tooltip: 'منوی بیشتر', onTap: () {
          haptic();
          showMoreHub(context);
        }),
        const SizedBox(width: 8),
        IconBtn(Icons.settings_outlined, tooltip: 'تنظیمات', onTap: () {
          haptic();
          Nav.push(context, '/settings');
        }),
      ]),
    );
  }

  Widget _pill(String label, bool active) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(color: active ? C.purple : Colors.transparent, borderRadius: BorderRadius.circular(999)),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: active ? Colors.white : C.slate400)),
      );
}

class BottomNav extends StatelessWidget {
  /// When shown on a pushed deadlines sub-page, taps pop back to the shell.
  final bool fromSubPage;
  final int? activeOverride;
  const BottomNav({super.key, this.fromSubPage = false, this.activeOverride});

  @override
  Widget build(BuildContext context) {
    final loading = context.select<PortfolioStore, bool>((s) => s.isLoadingData);
    return ValueListenableBuilder<int>(
      valueListenable: shellTab,
      builder: (_, tab, __) {
        final active = activeOverride ?? tab;
        void go(int i) {
          haptic();
          shellTab.value = i;
          if (fromSubPage) Navigator.of(context).popUntil((r) => r.isFirst);
        }

        return Container(
          decoration: const BoxDecoration(color: Color(0xE61A1B26), border: Border(top: BorderSide(color: C.borderSoft))),
          padding: EdgeInsets.fromLTRB(12, 6, 12, MediaQuery.of(context).padding.bottom + 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            _NavItem(icon: Icons.home_outlined, label: 'داشبورد', active: active == 0, onTap: () => go(0)),
            _NavItem(icon: Icons.show_chart, label: 'دارایی‌ها', active: active == 1, onTap: () => go(1)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Opacity(
                opacity: loading ? 0.5 : 1,
                child: GestureDetector(
                  onTap: loading
                      ? null
                      : () {
                          haptic();
                          Nav.push(context, '/transactions/new');
                        },
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: C.purple,
                      shape: BoxShape.circle,
                      border: Border.all(color: C.shell, width: 5),
                      boxShadow: [BoxShadow(color: C.purple.withValues(alpha: 0.5), blurRadius: 15, offset: const Offset(0, 4))],
                    ),
                    child: const Icon(Icons.add, color: Colors.white, size: 26),
                  ),
                ),
              ),
            ),
            _NavItem(icon: Icons.account_balance_wallet_outlined, label: 'کیف پول‌ها', active: active == 2, disabled: loading, onTap: () => go(2)),
            _NavItem(icon: Icons.calendar_month_outlined, label: 'سررسید', active: active == 3, onTap: () => go(3)),
          ]),
        );
      },
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final bool disabled;
  final VoidCallback onTap;
  const _NavItem({required this.icon, required this.label, required this.active, required this.onTap, this.disabled = false});
  @override
  Widget build(BuildContext context) {
    final color = active ? C.purple400 : C.slate500;
    return Expanded(
      child: Opacity(
        opacity: disabled ? 0.5 : 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: disabled ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: active ? C.purple500.withValues(alpha: 0.2) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, size: 22, color: color),
              ),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: color)),
            ]),
          ),
        ),
      ),
    );
  }
}

const _moreLinks = [
  ('/transactions', 'تراکنش‌ها', 'جستجو، فیلتر و خروجی CSV', Icons.receipt_long_outlined),
  ('/reports', 'گزارش‌ها', 'جریان نقدی و سود/زیان دارایی', Icons.bar_chart),
  ('/prices', 'قیمت‌ها و نرخ‌ها', 'قیمت روزانه و نرخ ارز', Icons.trending_up),
  ('/manage/assets', 'مدیریت دارایی‌ها', 'افزودن، ویرایش و مرتب‌سازی', Icons.toll_outlined),
  ('/plan', 'برنامه هزینه', 'پیش‌بینی هزینه‌های ماهانه', Icons.calculate_outlined),
  ('/manage/goals', 'اهداف تخصیص', 'درصد یا مقدار هدف', Icons.track_changes),
  ('/manage/recurring', 'تراکنش‌های دوره‌ای', 'حقوق، اجاره و … — ثبت خودکار', Icons.repeat),
  ('/manage/import', 'ورود CSV', 'درآمد و هزینه دسته‌ای', Icons.upload_file_outlined),
  ('/manage/categories', 'دسته‌بندی‌ها', 'درآمد، هزینه و دارایی', Icons.grid_view_outlined),
];

void showMoreHub(BuildContext context) {
  showAppSheet(context, title: 'بیشتر', builder: (ctx) {
    return Column(children: [
      for (final (href, title, sub, icon) in _moreLinks)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AppCard(
            radius: 16,
            onTap: () {
              Navigator.pop(ctx);
              Nav.push(context, href);
            },
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: C.purple500.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, size: 20, color: C.purple400),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: C.slate200)),
                  Text(sub, style: const TextStyle(fontSize: 11, color: C.slate500)),
                ]),
              ),
            ]),
          ),
        ),
    ]);
  });
}
