// Pushes each sub page on the root navigator, the way Nav.push does, and
// fails if a page throws while building (release builds show a blank page).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharjook/app/router.dart';
import 'package:kharjook/core/store.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _paths = [
  '/transactions',
  '/transactions/new',
  '/transactions/new?type=TRANSFER&personId=p&walletId=w&amount=10&personSide=source',
  '/deadlines/persons',
  '/deadlines/persons/missing',
  '/deadlines/loans',
  '/deadlines/checks',
  '/deadlines/subscriptions',
  '/deadlines/subscriptions/new',
  '/reports',
  '/reports/cashflow?period=month',
  '/reports/assets?period=year',
  '/prices',
  '/plan',
  '/manage/goals',
  '/manage/categories',
  '/manage/recurring',
  '/manage/import',
  '/manage/assets',
  '/manage/wallets',
  '/settings',
];

void main() {
  for (final path in _paths) {
    testWidgets('renders $path', (tester) async {
      final store = PortfolioStore()
        ..user = User(id: 'u1', appMetadata: const {}, userMetadata: const {}, aud: 'authenticated', createdAt: '2026-01-01T00:00:00Z');
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(
          navigatorKey: rootNavigatorKey,
          builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
          home: const Scaffold(body: Text('home')),
        ),
      ));
      Nav.push(rootNavigatorKey.currentContext!, path);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      expect(find.byType(ErrorWidget), findsNothing);
    });
  }
}
