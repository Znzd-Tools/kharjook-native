// Path-based navigation mirroring the web app's URLs, so every link
// (`router.push('/assets/123')`, `/transactions/new?type=SELL&assetId=…`)
// has one native counterpart.

import 'package:flutter/material.dart';

import '../features/assets/asset_details_screen.dart';
import '../features/assets/manage_assets_screen.dart';
import '../features/categories/manage_categories_screen.dart';
import '../features/deadlines/checks_screens.dart';
import '../features/deadlines/loans_screens.dart';
import '../features/deadlines/subscriptions_screens.dart';
import '../features/goals/manage_goals_screen.dart';
import '../features/persons/persons_screens.dart';
import '../features/plan/expense_plan_screen.dart';
import '../features/prices/prices_screen.dart';
import '../features/reports/assets_report_screen.dart';
import '../features/reports/cashflow_report_screen.dart';
import '../features/reports/reports_index_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/transactions/add_transaction_screen.dart';
import '../features/transactions/import_screen.dart';
import '../features/transactions/recurring_screen.dart';
import '../features/transactions/transactions_screen.dart';
import '../features/wallets/manage_wallets_screen.dart';
import '../features/wallets/wallet_details_screen.dart';
import 'shell.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

const _tabs = {'/': 0, '/assets': 1, '/wallets': 2, '/deadlines': 3};

class Nav {
  static Future<T?> push<T>(BuildContext context, String path) {
    final uri = Uri.parse(path);
    final tab = _tabs[uri.path];
    final nav = rootNavigatorKey.currentState ?? Navigator.of(context);
    if (tab != null) {
      shellTab.value = tab;
      nav.popUntil((r) => r.isFirst);
      return Future.value(null);
    }
    final page = _resolve(uri);
    return nav.push<T>(MaterialPageRoute(builder: (_) => page, settings: RouteSettings(name: path)));
  }

  static Future<T?> replace<T>(BuildContext context, String path) {
    final uri = Uri.parse(path);
    final nav = rootNavigatorKey.currentState ?? Navigator.of(context);
    if (_tabs.containsKey(uri.path)) return push(context, path);
    return nav.pushReplacement<T, void>(MaterialPageRoute(builder: (_) => _resolve(uri), settings: RouteSettings(name: path)));
  }

  static void back(BuildContext context) => Navigator.of(context).maybePop();
}

Widget _withNav(Widget page) => _DeadlineSubPage(child: page);

class _DeadlineSubPage extends StatelessWidget {
  final Widget child;
  const _DeadlineSubPage({required this.child});
  @override
  Widget build(BuildContext context) => Scaffold(body: child, bottomNavigationBar: const BottomNav(fromSubPage: true, activeOverride: 3));
}

Widget _resolve(Uri uri) {
  final seg = uri.pathSegments;
  final q = uri.queryParameters;
  String p(int i) => i < seg.length ? seg[i] : '';
  switch (p(0)) {
    case 'assets':
      return AssetDetailsScreen(assetId: p(1));
    case 'wallets':
      return WalletDetailsScreen(walletId: p(1));
    case 'transactions':
      if (p(1).isEmpty) return const TransactionsScreen();
      if (p(1) == 'new') return AddTransactionScreen.fromQuery(q);
      return AddTransactionScreen(transactionId: p(1));
    case 'settings':
      return const SettingsScreen();
    case 'reports':
      if (p(1) == 'cashflow') return CashflowReportScreen(query: q);
      if (p(1) == 'assets') return AssetsReportScreen(query: q);
      return const ReportsIndexScreen();
    case 'prices':
      return PricesScreen(query: q);
    case 'plan':
      return const ExpensePlanScreen();
    case 'manage':
      switch (p(1)) {
        case 'goals':
          return const ManageGoalsScreen();
        case 'wallets':
          return const ManageWalletsScreen();
        case 'assets':
          return const ManageAssetsScreen();
        case 'categories':
          return const ManageCategoriesScreen();
        case 'recurring':
          return const RecurringScreen();
        case 'import':
          return const ImportScreen();
        case 'rates':
          return const PricesScreen(query: {});
        case 'price-sources':
          return const PricesScreen(query: {'tab': 'sources', 'advanced': '1'});
      }
    case 'deadlines':
      final id = p(2);
      switch (p(1)) {
        case 'loans':
          if (id.isEmpty) return _withNav(const LoansHubScreen());
          if (id == 'new') return const LoanFormScreen();
          return LoanFormScreen(loanId: id);
        case 'checks':
          if (id.isEmpty) return _withNav(const ChecksHubScreen());
          if (id == 'new') return const CheckFormScreen();
          return CheckFormScreen(checkId: id);
        case 'subscriptions':
          if (id.isEmpty) return const SubscriptionsHubScreen();
          if (id == 'new') return const SubscriptionFormScreen();
          return SubscriptionFormScreen(subscriptionId: id);
        case 'persons':
          if (id.isEmpty) return _withNav(const ManagePersonsScreen());
          return PersonDetailScreen(personId: id);
      }
  }
  return const _NotFound();
}

class _NotFound extends StatelessWidget {
  const _NotFound();
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('صفحه پیدا نشد.')),
      );
}
