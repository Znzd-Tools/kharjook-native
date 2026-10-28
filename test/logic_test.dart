// Ports of the web app's vitest suites for the shared ledger + format logic.

import 'package:flutter_test/flutter_test.dart';
import 'package:kharjook/core/logic/ledger.dart';
import 'package:kharjook/core/models.dart';
import 'package:kharjook/core/utils/format.dart';
import 'package:kharjook/core/utils/jalali.dart';

final testAsset = Asset(id: 'a1', userId: 'u1', name: 'طلا', unit: 'گرم', decimalPlaces: 2, priceToman: 1000, priceUsd: 10);
Asset withPrice(double t, double u) =>
    Asset(id: 'a1', userId: 'u1', name: 'طلا', unit: 'گرم', decimalPlaces: 2, priceToman: t, priceUsd: u);

var _seq = 0;
Transaction makeTx(Json partial) {
  _seq += 1;
  return Transaction.fromJson({
    'id': 't$_seq',
    'user_id': 'u1',
    'date_string': '1403/01/01',
    'created_at': '2024-01-01T00:00:${(_seq % 60).toString().padLeft(2, '0')}Z',
    'usd_rate': 100,
    ...partial,
  });
}

Transaction buy(String date, double qty, double price, [String? createdAt]) => makeTx({
      'created_at': ?createdAt,
      'type': 'BUY',
      'date_string': date,
      'target_asset_id': 'a1',
      'target_amount': qty,
      'asset_id': 'a1',
      'amount': qty,
      'price_toman': price,
    });

Transaction sell(String date, double qty, double price, [String? createdAt]) => makeTx({
      'created_at': ?createdAt,
      'type': 'SELL',
      'date_string': date,
      'source_asset_id': 'a1',
      'source_amount': qty,
      'asset_id': 'a1',
      'amount': qty,
      'price_toman': price,
    });

void main() {
  group('formatAssetAmount', () {
    test('exact decimals', () {
      expect(formatAssetAmount(0.29, 2), '0.29');
      expect(formatAssetAmount(1.13, 2), '1.13');
      expect(formatAssetAmount(9.95, 2), '9.95');
      expect(formatAssetAmount(1.005, 3), '1.005');
    });
    test('float noise', () {
      expect(formatAssetAmount(5 - 4.9, 1), '0.1');
      expect(formatAssetAmount(3 - 0.1 - 0.2, 1), '2.7');
      expect(formatAssetAmount(1 - 0.9, 4), '0.1');
    });
    test('truncates real fractions', () {
      expect(formatAssetAmount(0.0999, 1), '0');
      expect(formatAssetAmount(1.23456789, 4), '1.2345');
      expect(formatAssetAmount(0.00000008, 8), '0.00000008');
    });
    test('grouping, sign, no negative zero', () {
      expect(formatAssetAmount(1234567.5, 2), '1,234,567.5');
      expect(formatAssetAmount(-2.5, 2), '-2.5');
      expect(formatAssetAmount(-1e-12, 4), '0');
      expect(formatAssetAmount(12, 0), '12');
      expect(formatAssetAmount(double.nan, 2), '0');
    });
  });

  group('calculateAssetStats', () {
    test('oversell realizes only held units', () {
      final s = calculateAssetStats(testAsset, [buy('1403/01/01', 1, 100), sell('1403/01/02', 3, 200)], 'TOMAN', 100);
      expect(s.realizedProfitToman, 100);
      expect(s.totalAmount, 0);
    });
    test('short covered by later buys', () {
      final txs = [buy('1403/01/01', 100, 100), sell('1403/01/02', 50, 100), sell('1403/01/03', 100, 200), buy('1403/01/04', 1000, 150)];
      final s = calculateAssetStats(testAsset, txs, 'TOMAN', 100);
      expect(s.totalAmount, 950);
      expect(s.totalCostToman, 950 * 150);
      expect(s.realizedProfitToman, 7500);
    });
    test('average cost', () {
      final s = calculateAssetStats(testAsset, [buy('1403/01/01', 2, 100), buy('1403/01/02', 2, 200), sell('1403/01/03', 1, 300)], 'TOMAN', 100);
      expect(s.realizedProfitToman, 150);
      expect(s.totalAmount, 3);
      expect(s.totalCostToman, 450);
    });
    test('polymorphic amount fallback', () {
      expect(assetQuantityFromTransactions('a1', [makeTx({'type': 'BUY', 'target_asset_id': 'a1', 'target_amount': 5, 'price_toman': 10})]), 5);
    });
    test('sell all then buy again same day', () {
      String t(int h) => '2024-07-22T0$h:00:00Z';
      final txs = [buy('1403/01/01', 10, 100, t(1)), sell('1403/02/01', 10, 120, t(2)), buy('1403/02/01', 10, 130, t(3))];
      final s = calculateAssetStats(withPrice(150, 10), txs, 'TOMAN', 100);
      expect(s.realizedProfitToman, 200);
      expect(s.totalCostToman, 1300);
      expect(s.unrealizedProfitToman, 200);
      expect(s.activeSinceDate, '1403/02/01');
    });
    test('buys-first fallback', () {
      String t(int h) => '2024-07-22T0$h:00:00Z';
      final s = calculateAssetStats(testAsset, [sell('1403/02/01', 5, 120, t(1)), buy('1403/02/01', 5, 100, t(2))], 'TOMAN', 100);
      expect(s.realizedProfitToman, 100);
      expect(s.totalAmount, 0);
    });
    test('trade price when no live price', () {
      final s = calculateAssetStats(withPrice(0, 0), [buy('1403/01/01', 2, 100), sell('1403/02/01', 1, 140)], 'TOMAN', 100);
      expect(s.currentPriceSource, 'trade');
      expect(s.currentPriceDate, '1403/02/01');
      expect(s.currentValueToman, 140);
      expect(s.unrealizedProfitToman, 40);
    });
  });

  group('jalali', () {
    test('round trip', () {
      expect(toJalaali(2024, 3, 20), const JDate(1403, 1, 1));
      final g = toGregorian(1403, 1, 1);
      expect([g.gy, g.gm, g.gd], [2024, 3, 20]);
      expect(jalaaliMonthLength(1403, 12), 30);
      expect(jalaaliMonthLength(1404, 12), 29);
      expect(parseDateToNumber('۱۴۰۳/۱/۵'), 14030105);
    });
    test('currency format', () {
      expect(formatCurrency(1234567, 'TOMAN'), '1,234,567 ت');
      expect(formatCurrency(-12.5, 'USD'), '-\$12.50');
    });
  });
}
