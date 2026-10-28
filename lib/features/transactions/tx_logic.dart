// Ports of transaction-form-types.ts, transaction-form-logic.ts,
// expense-transaction.ts and convert-transaction.ts.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/logic/ledger.dart';
import '../../core/models.dart';
import '../../core/ui/theme.dart';
import '../../core/utils/digits.dart';
import '../../core/utils/format.dart';
import '../../core/utils/jalali.dart';

typedef EndpointKind = String; // wallet | asset | person

class CurrencyMeta {
  final String code, label, symbol;
  final int decimals;
  const CurrencyMeta(this.code, this.label, this.symbol, this.decimals);
}

const kCurrencyMeta = {
  'IRT': CurrencyMeta('IRT', 'تومان', 'ت', 0),
  'USD': CurrencyMeta('USD', 'دلار آمریکا', '\$', 2),
  'TRY': CurrencyMeta('TRY', 'لیر ترکیه', '₺', 2),
  'EUR': CurrencyMeta('EUR', 'یورو', '€', 2),
};
CurrencyMeta currencyMeta(String c) => kCurrencyMeta[c] ?? CurrencyMeta(c, c, c, 2);

/// JS `Number(s)` for form strings.
double n(String s) => canonicalToNumber(s);
bool _okPos(double v) => v.isFinite && v > 0;

/// JS `String(number)`.
String jsNumStr(double? v) {
  if (v == null) return '';
  if (v.isFinite && v == v.truncateToDouble() && v.abs() < 1e21) return v.toInt().toString();
  return v.toString();
}

/// canonicalNumber: up to 10 decimals, trimmed.
String canonicalNumber(double v) {
  if (!v.isFinite) return '';
  final rounded = v.toStringAsFixed(10);
  var t = rounded;
  if (t.contains('.')) {
    t = t.replaceAll(RegExp(r'0+$'), '');
    if (t.endsWith('.')) t = t.substring(0, t.length - 1);
  }
  return t.isEmpty || t == '-0' ? '0' : t;
}

class TxForm {
  String type;
  String date;
  EndpointKind? sourceKind;
  String? sourceId;
  EndpointKind? targetKind;
  String? targetId;
  String sourceAmount;
  String targetAmount;
  String priceToman;
  String usdRate;
  String? categoryId;
  String note;

  TxForm({
    required this.type,
    required this.date,
    this.sourceKind,
    this.sourceId,
    this.targetKind,
    this.targetId,
    this.sourceAmount = '',
    this.targetAmount = '',
    this.priceToman = '',
    this.usdRate = '',
    this.categoryId,
    this.note = '',
  });

  TxForm copy() => TxForm(
        type: type,
        date: date,
        sourceKind: sourceKind,
        sourceId: sourceId,
        targetKind: targetKind,
        targetId: targetId,
        sourceAmount: sourceAmount,
        targetAmount: targetAmount,
        priceToman: priceToman,
        usdRate: usdRate,
        categoryId: categoryId,
        note: note,
      );
}

const kPrimarySide = {'BUY': 'target', 'SELL': 'source', 'TRANSFER': 'source', 'INCOME': 'target', 'EXPENSE': 'source'};

class TypeShape {
  final List<String>? source;
  final List<String>? target;
  final String? needsCategory;
  const TypeShape(this.source, this.target, this.needsCategory);
}

const kTypeShapes = {
  'BUY': TypeShape(['wallet'], ['asset'], null),
  'SELL': TypeShape(['asset'], ['wallet'], null),
  'TRANSFER': TypeShape(['wallet', 'asset', 'person'], ['wallet', 'asset', 'person'], null),
  'INCOME': TypeShape(null, ['wallet', 'asset', 'person'], 'income'),
  'EXPENSE': TypeShape(['wallet', 'asset', 'person'], null, 'expense'),
};

class TypeStyle {
  final String label;
  final Color accent;
  const TypeStyle(this.label, this.accent);
}

const kConvertMode = 'CONVERT';
const kConvertNotePrefix = '[CONVERT]';
const kTypeStyles = {
  'BUY': TypeStyle('خرید', C.purple),
  'SELL': TypeStyle('فروش', Color(0xFFD97706)),
  'TRANSFER': TypeStyle('انتقال', Color(0xFF0284C7)),
  'INCOME': TypeStyle('درآمد', Color(0xFF059669)),
  'EXPENSE': TypeStyle('هزینه', Color(0xFFE11D48)),
  kConvertMode: TypeStyle('تبدیل', Color(0xFF7C3AED)),
};
const kUiTabs = ['BUY', 'SELL', kConvertMode, 'TRANSFER', 'INCOME', 'EXPENSE'];

class PricingContext {
  final bool needsPrice;
  final bool showTomanPrice;
  final bool needsUsdRate;
  final String priceLabel;
  final String? endpointKind;
  final String? walletCurrency;
  const PricingContext(this.needsPrice, this.needsUsdRate, this.priceLabel, this.endpointKind, this.walletCurrency, {this.showTomanPrice = true});
}

Wallet? _findWallet(List<Wallet> ws, String? id) {
  if (id == null) return null;
  for (final w in ws) {
    if (w.id == id) return w;
  }
  return null;
}

Asset? findAsset(List<Asset> as, String? id) {
  if (id == null) return null;
  for (final a in as) {
    if (a.id == id) return a;
  }
  return null;
}

Wallet? findWallet(List<Wallet> ws, String? id) => _findWallet(ws, id);

Wallet? walletFromForm(TxForm f, String side, List<Wallet> wallets) {
  final kind = side == 'source' ? f.sourceKind : f.targetKind;
  final id = side == 'source' ? f.sourceId : f.targetId;
  if (kind != 'wallet' || id == null) return null;
  return _findWallet(wallets, id);
}

PricingContext pricingContextOf(TxForm f, List<Wallet> wallets) {
  if (f.type == 'TRANSFER') {
    final w2a = f.sourceKind == 'wallet' && f.targetKind == 'asset' && f.sourceId != null && f.targetId != null;
    final a2w = f.sourceKind == 'asset' && f.targetKind == 'wallet' && f.sourceId != null && f.targetId != null;
    if (w2a) return const PricingContext(true, true, 'قیمت خرید هر واحد (تومان)', 'asset', null);
    if (a2w) return const PricingContext(true, true, 'قیمت فروش هر واحد (تومان)', 'asset', null);
    return const PricingContext(false, false, '', null, null);
  }
  if (f.type == 'BUY' || f.type == 'SELL') {
    final w = f.type == 'BUY' ? walletFromForm(f, 'source', wallets) : walletFromForm(f, 'target', wallets);
    return PricingContext(true, true, 'قیمت واحد (تومان)', 'asset', w?.currency);
  }
  final kind = f.type == 'INCOME' ? f.targetKind : f.sourceKind;
  final id = f.type == 'INCOME' ? f.targetId : f.sourceId;
  if (kind == 'asset') return const PricingContext(true, true, 'قیمت هر واحد دارایی (تومان)', 'asset', null);
  if (kind == 'person') return const PricingContext(false, false, '', 'person', null);
  if (kind == 'wallet' && id != null) {
    final w = _findWallet(wallets, id);
    if (w == null) return const PricingContext(false, false, '', 'wallet', null);
    if (w.currency == 'IRT') return const PricingContext(false, false, '', 'wallet', 'IRT');
    return PricingContext(true, true, 'قیمت هر ${currencyMeta(w.currency).label} (تومان)', 'wallet', w.currency);
  }
  return const PricingContext(false, false, '', null, null);
}

String? endpointKindOfTx(Transaction tx, String side) {
  if (side == 'source') {
    if (tx.sourceWalletId != null) return 'wallet';
    if (tx.sourceAssetId != null) return 'asset';
    if (tx.sourcePersonId != null) return 'person';
    return null;
  }
  if (tx.targetWalletId != null) return 'wallet';
  if (tx.targetAssetId != null) return 'asset';
  if (tx.targetPersonId != null) return 'person';
  return null;
}

String? endpointIdOfTx(Transaction tx, String side) => side == 'source'
    ? (tx.sourceWalletId ?? tx.sourceAssetId ?? tx.sourcePersonId)
    : (tx.targetWalletId ?? tx.targetAssetId ?? tx.targetPersonId);

class FormDefaults {
  final String? assetId, walletId, defaultType, personId, personSide, settleAmount;
  const FormDefaults({this.assetId, this.walletId, this.defaultType, this.personId, this.personSide, this.settleAmount});
}

TxForm buildInitialForm(Transaction? tx, FormDefaults d, double usdRate) {
  if (tx != null) {
    return TxForm(
      type: tx.type,
      date: latinizeDigits(tx.dateString),
      sourceKind: endpointKindOfTx(tx, 'source'),
      sourceId: endpointIdOfTx(tx, 'source'),
      targetKind: endpointKindOfTx(tx, 'target'),
      targetId: endpointIdOfTx(tx, 'target'),
      sourceAmount: tx.sourceAmount != null ? jsNumStr(tx.sourceAmount) : '',
      targetAmount: tx.targetAmount != null ? jsNumStr(tx.targetAmount) : '',
      priceToman: tx.priceToman != null ? jsNumStr(tx.priceToman) : '',
      usdRate: tx.usdRate != null ? jsNumStr(tx.usdRate) : jsNumStr(usdRate),
      categoryId: tx.categoryId,
      note: tx.note ?? '',
    );
  }
  final type = d.defaultType ?? 'BUY';
  final f = TxForm(type: type, date: todayStr(), usdRate: jsNumStr(usdRate));
  if (d.assetId != null) {
    if (type == 'BUY') {
      f.targetKind = 'asset';
      f.targetId = d.assetId;
    } else if (type == 'SELL' || type == 'EXPENSE' || type == 'TRANSFER') {
      f.sourceKind = 'asset';
      f.sourceId = d.assetId;
    } else if (type == 'INCOME') {
      f.targetKind = 'asset';
      f.targetId = d.assetId;
    }
  }
  if (d.personId != null && d.walletId != null && d.settleAmount != null && d.personSide != null && type == 'TRANSFER') {
    if (d.personSide == 'source') {
      f.sourceKind = 'person';
      f.sourceId = d.personId;
      f.targetKind = 'wallet';
      f.targetId = d.walletId;
    } else {
      f.sourceKind = 'wallet';
      f.sourceId = d.walletId;
      f.targetKind = 'person';
      f.targetId = d.personId;
    }
    f.sourceAmount = d.settleAmount!;
    f.targetAmount = d.settleAmount!;
    return f;
  }
  if (d.walletId != null) {
    if (type == 'SELL' || type == 'INCOME') {
      f.targetKind = 'wallet';
      f.targetId = d.walletId;
    } else {
      f.sourceKind = 'wallet';
      f.sourceId = d.walletId;
    }
  }
  return f;
}

TxForm recomputeMoneySide(TxForm next, List<Wallet> wallets, List<CurrencyRate> rates, double usdRate) {
  if (next.type != 'BUY' && next.type != 'SELL') return next;
  final w = next.type == 'BUY' ? walletFromForm(next, 'source', wallets) : walletFromForm(next, 'target', wallets);
  if (w == null) {
    final c = next.copy();
    if (next.type == 'BUY') {
      c.sourceAmount = '';
    } else {
      c.targetAmount = '';
    }
    return c;
  }
  final price = n(next.priceToman);
  if (!_okPos(price)) return next;
  double rate;
  if (w.currency == 'USD') {
    final o = n(next.usdRate);
    rate = _okPos(o) ? o : usdRate;
  } else if (w.currency == 'IRT') {
    rate = 1;
  } else {
    rate = tomanPerUnit(w.currency, rates);
  }
  if (rate == 0 || rate.isNaN) return next;
  final c = next.copy();
  if (next.type == 'BUY') {
    final tgt = n(next.targetAmount);
    if (!_okPos(tgt)) return next;
    c.sourceAmount = canonicalNumber((tgt * price) / rate);
    return c;
  }
  final src = n(next.sourceAmount);
  if (!_okPos(src)) return next;
  c.targetAmount = canonicalNumber((src * price) / rate);
  return c;
}

double walletRateForTransfer(Wallet w, List<CurrencyRate> rates, double globalUsd, [String? formUsd]) {
  if (w.currency == 'IRT') return 1;
  if (w.currency == 'USD') {
    final o = formUsd != null ? n(formUsd) : double.nan;
    final u = _okPos(o) ? o : globalUsd;
    return u > 0 ? u : tomanPerUnit('USD', rates);
  }
  return tomanPerUnit(w.currency, rates);
}

TxForm recomputeTransferTarget(TxForm next, List<Wallet> wallets, List<Asset> assets, List<CurrencyRate> rates, double usdRate) {
  if (next.type != 'TRANSFER') return next;
  final srcAmount = n(next.sourceAmount);
  if (!_okPos(srcAmount)) return next;
  if (next.sourceKind == null || next.sourceId == null || next.targetKind == null || next.targetId == null) return next;
  final sw = next.sourceKind == 'wallet' ? _findWallet(wallets, next.sourceId) : null;
  final tw = next.targetKind == 'wallet' ? _findWallet(wallets, next.targetId) : null;
  final sa = next.sourceKind == 'asset' ? findAsset(assets, next.sourceId) : null;
  final ta = next.targetKind == 'asset' ? findAsset(assets, next.targetId) : null;
  if (sw != null && tw != null) {
    if (sw.currency == tw.currency) return next.copy()..targetAmount = next.sourceAmount;
    return next;
  }
  if (sa != null && tw != null) {
    final wr = walletRateForTransfer(tw, rates, usdRate, next.usdRate);
    final op = n(next.priceToman);
    final ap = _okPos(op) ? op : sa.priceToman;
    if (!(wr > 0) || !(ap > 0)) return next;
    return next.copy()..targetAmount = canonicalNumber((srcAmount * ap) / wr);
  }
  if (sw != null && ta != null) {
    final wr = walletRateForTransfer(sw, rates, usdRate, next.usdRate);
    final op = n(next.priceToman);
    final ap = _okPos(op) ? op : ta.priceToman;
    if (!(wr > 0) || !(ap > 0)) return next;
    return next.copy()..targetAmount = canonicalNumber((srcAmount * wr) / ap);
  }
  return next;
}

double assetHolding(String assetId, List<Transaction> txs) => assetQuantityFromTransactions(assetId, txs);

double personBalanceById(String personId, List<Transaction> txs) {
  var b = 0.0;
  for (final tx in txs) {
    if (tx.targetPersonId == personId) b += numOr0(tx.targetAmount);
    if (tx.sourcePersonId == personId) b -= numOr0(tx.sourceAmount);
  }
  return b;
}

double? sourceBalance(TxForm f, List<Wallet> wallets, List<Transaction> txs, List<Person> persons) {
  if (f.sourceKind == 'wallet' && f.sourceId != null) {
    final w = _findWallet(wallets, f.sourceId);
    if (w == null) return null;
    return calculateWalletStats(w, txs).balance;
  }
  if (f.sourceKind == 'asset' && f.sourceId != null) return assetHolding(f.sourceId!, txs);
  if (f.sourceKind == 'person' && f.sourceId != null) {
    if (!persons.any((p) => p.id == f.sourceId)) return null;
    return personBalanceById(f.sourceId!, txs);
  }
  return null;
}

String? validateForm(TxForm f, List<Wallet> wallets) {
  if (f.date.isEmpty) return 'تاریخ الزامی است.';
  if (parseJalaali(f.date) == null) return 'تاریخ نامعتبر است.';
  switch (f.type) {
    case 'BUY':
      if (f.targetKind != 'asset' || f.targetId == null) return 'دارایی مقصد را انتخاب کن.';
      if (f.sourceKind != null && f.sourceKind != 'wallet') return 'مبدأ خرید فقط می‌تواند کیف پول باشد.';
    case 'SELL':
      if (f.sourceKind != 'asset' || f.sourceId == null) return 'دارایی مبدأ را انتخاب کن.';
      if (f.targetKind != null && f.targetKind != 'wallet') return 'مقصد فروش فقط می‌تواند کیف پول باشد.';
    case 'TRANSFER':
      if (f.sourceKind == null || f.sourceId == null) return 'مبدأ را انتخاب کن.';
      if (f.targetKind == null || f.targetId == null) return 'مقصد را انتخاب کن.';
      if (f.sourceKind == 'asset' && f.targetKind == 'person') return 'انتقال دارایی به شخص مجاز نیست.';
      if (f.sourceKind == 'person' && f.targetKind == 'asset') return 'انتقال از شخص به دارایی مجاز نیست.';
      if (f.sourceKind == 'asset' && f.targetKind == 'asset') return 'برای جابه‌جایی بین دو دارایی از «تبدیل» استفاده کن.';
      if (f.sourceId == f.targetId) return 'مبدأ و مقصد نباید یکی باشند.';
    case 'INCOME':
      if (f.targetKind == null || f.targetId == null) return 'مقصد را انتخاب کن.';
      if (f.categoryId == null) return 'دسته درآمد الزامی است.';
    case 'EXPENSE':
      if (f.sourceKind == null || f.sourceId == null) return 'مبدأ را انتخاب کن.';
      if (f.categoryId == null) return 'دسته هزینه الزامی است.';
  }
  final ctx = pricingContextOf(f, wallets);
  if (ctx.needsPrice && ctx.showTomanPrice) {
    if (!_okPos(n(f.priceToman))) return 'قیمت واحد (تومان) نامعتبر است.';
  }
  if (ctx.needsUsdRate) {
    if (!_okPos(n(f.usdRate))) return 'نرخ دلار نامعتبر است.';
  }
  final needsSrc = f.type == 'SELL' || f.type == 'EXPENSE' || f.type == 'TRANSFER' || (f.type == 'BUY' && f.sourceKind == 'wallet' && f.sourceId != null);
  final needsTgt = f.type == 'BUY' || f.type == 'INCOME' || f.type == 'TRANSFER' || (f.type == 'SELL' && f.targetKind == 'wallet' && f.targetId != null);
  if (needsSrc && !_okPos(n(f.sourceAmount))) return 'مقدار مبدأ نامعتبر است.';
  if (needsTgt && !_okPos(n(f.targetAmount))) return 'مقدار مقصد نامعتبر است.';
  return null;
}

String? sourceEndpointKey(TxForm f) => f.sourceKind == null || f.sourceId == null ? null : '${f.sourceKind}:${f.sourceId}';

String? validateSourceFunds(TxForm f, List<Wallet> wallets, List<Transaction> txs, List<Person> persons, [double reserved = 0]) {
  if (f.type == 'INCOME' || f.sourceKind == 'person') return null;
  final bal = sourceBalance(f, wallets, txs, persons);
  final amount = n(f.sourceAmount);
  if (bal != null && amount.isFinite && amount + reserved > bal + 1e-9) return 'موجودی مبدأ کافی نیست.';
  return null;
}

class Snap {
  final double? toman, usd;
  const Snap(this.toman, this.usd);
  static const none = Snap(null, null);
}

Snap _fromAmountPrice(double amount, double price, double? validUsd) {
  final t = amount * price;
  return Snap(t, validUsd != null ? t / validUsd : null);
}

Snap computeExpenseAmountSnapshots(TxForm f, List<Wallet> wallets, List<CurrencyRate> rates, double fallbackUsd) {
  final u = n(f.usdRate);
  final valid = _okPos(u) ? u : null;
  final amount = n(f.sourceAmount);
  if (!_okPos(amount)) return Snap.none;
  if (f.sourceKind == 'asset') {
    final p = n(f.priceToman);
    if (!_okPos(p)) return Snap.none;
    return _fromAmountPrice(amount, p, valid);
  }
  if (f.sourceKind == 'wallet' && f.sourceId != null) {
    final w = _findWallet(wallets, f.sourceId);
    if (w == null) return Snap.none;
    if (w.currency == 'IRT') return _fromAmountPrice(amount, 1, valid);
    final explicit = n(f.priceToman);
    final price = _okPos(explicit) ? explicit : walletRateForTransfer(w, rates, fallbackUsd, f.usdRate);
    if (!(price > 0)) return Snap.none;
    return _fromAmountPrice(amount, price, valid);
  }
  if (f.sourceKind == 'person') return _fromAmountPrice(amount, 1, valid);
  return Snap.none;
}

Snap computeAmountSnapshots(TxForm f, List<Wallet> wallets, List<CurrencyRate> rates, double fallbackUsd) {
  final u = n(f.usdRate);
  final valid = _okPos(u) ? u : null;
  switch (f.type) {
    case 'BUY':
    case 'SELL':
      final amount = f.type == 'BUY' ? n(f.targetAmount) : n(f.sourceAmount);
      final price = n(f.priceToman);
      if (!_okPos(amount) || !_okPos(price)) return Snap.none;
      return _fromAmountPrice(amount, price, valid);
    case 'INCOME':
      final amount = n(f.targetAmount);
      if (!_okPos(amount)) return Snap.none;
      if (f.targetKind == 'asset') {
        final p = n(f.priceToman);
        if (!_okPos(p)) return Snap.none;
        return _fromAmountPrice(amount, p, valid);
      }
      if (f.targetKind == 'wallet' && f.targetId != null) {
        final w = _findWallet(wallets, f.targetId);
        if (w == null) return Snap.none;
        if (w.currency == 'IRT') return _fromAmountPrice(amount, 1, valid);
        final explicit = n(f.priceToman);
        final price = _okPos(explicit) ? explicit : walletRateForTransfer(w, rates, fallbackUsd, f.usdRate);
        if (!(price > 0)) return Snap.none;
        return _fromAmountPrice(amount, price, valid);
      }
      if (f.targetKind == 'person') return _fromAmountPrice(amount, 1, valid);
      return Snap.none;
    case 'EXPENSE':
      return computeExpenseAmountSnapshots(f, wallets, rates, fallbackUsd);
    default:
      return Snap.none;
  }
}

/// JSON can't hold NaN; JS sends NaN as `null` via JSON.stringify.
double? _j(double v) => v.isFinite ? v : null;

Json buildPayload(TxForm f, String userId, List<Wallet> wallets, List<CurrencyRate> rates, double fallbackUsd) {
  final base = <String, dynamic>{
    'user_id': userId,
    'type': f.type,
    'date_string': f.date,
    'note': f.note.isEmpty ? null : f.note,
    'source_wallet_id': null,
    'source_asset_id': null,
    'source_person_id': null,
    'target_wallet_id': null,
    'target_asset_id': null,
    'target_person_id': null,
    'source_amount': null,
    'target_amount': null,
    'category_id': null,
    'asset_id': null,
    'amount': null,
    'price_toman': null,
    'usd_rate': null,
    'amount_toman_at_time': null,
    'amount_usd_at_time': null,
  };
  void setSource() {
    if (f.sourceKind == 'wallet') {
      base['source_wallet_id'] = f.sourceId;
    } else if (f.sourceKind == 'asset') {
      base['source_asset_id'] = f.sourceId;
    } else if (f.sourceKind == 'person') {
      base['source_person_id'] = f.sourceId;
    }
    final a = n(f.sourceAmount);
    if (_okPos(a)) base['source_amount'] = a;
  }

  void setTarget() {
    if (f.targetKind == 'wallet') {
      base['target_wallet_id'] = f.targetId;
    } else if (f.targetKind == 'asset') {
      base['target_asset_id'] = f.targetId;
    } else if (f.targetKind == 'person') {
      base['target_person_id'] = f.targetId;
    }
    final a = n(f.targetAmount);
    if (_okPos(a)) base['target_amount'] = a;
  }

  switch (f.type) {
    case 'BUY':
      setSource();
      setTarget();
      base['price_toman'] = _j(n(f.priceToman));
      base['usd_rate'] = _j(n(f.usdRate));
      base['asset_id'] = f.targetId;
      base['amount'] = _j(n(f.targetAmount));
    case 'SELL':
      setSource();
      setTarget();
      base['price_toman'] = _j(n(f.priceToman));
      base['usd_rate'] = _j(n(f.usdRate));
      base['asset_id'] = f.sourceId;
      base['amount'] = _j(n(f.sourceAmount));
    case 'TRANSFER':
      setSource();
      setTarget();
      if ((f.sourceKind == 'asset' && f.targetKind == 'wallet') || (f.sourceKind == 'wallet' && f.targetKind == 'asset')) {
        final assetIsSource = f.sourceKind == 'asset';
        final qty = n(assetIsSource ? f.sourceAmount : f.targetAmount);
        final money = n(assetIsSource ? f.targetAmount : f.sourceAmount);
        final w = _findWallet(wallets, assetIsSource ? f.targetId : f.sourceId);
        final wr = w != null ? walletRateForTransfer(w, rates, fallbackUsd, f.usdRate) : 0.0;
        final ep = n(f.priceToman);
        final fromPrice = _okPos(ep) && qty > 0 ? qty * ep : 0.0;
        final fromMoney = money.isFinite && wr.isFinite ? money * wr : 0.0;
        final toman = fromPrice > 0 ? fromPrice : fromMoney;
        if (qty > 0 && toman > 0) {
          base['asset_id'] = assetIsSource ? f.sourceId : f.targetId;
          base['amount'] = qty;
          base['price_toman'] = toman / qty;
          final u = n(f.usdRate);
          if (u > 0) base['usd_rate'] = u;
        }
      }
    case 'INCOME':
      setTarget();
      base['category_id'] = f.categoryId;
      if (f.targetKind == 'asset') {
        base['asset_id'] = f.targetId;
        base['amount'] = _j(n(f.targetAmount));
        base['price_toman'] = _j(n(f.priceToman));
        base['usd_rate'] = _j(n(f.usdRate));
      }
    case 'EXPENSE':
      if (f.sourceKind == 'wallet') {
        base['source_wallet_id'] = f.sourceId;
      } else if (f.sourceKind == 'asset') {
        base['source_asset_id'] = f.sourceId;
      } else if (f.sourceKind == 'person') {
        base['source_person_id'] = f.sourceId;
      }
      final a = n(f.sourceAmount);
      if (_okPos(a)) base['source_amount'] = a;
      base['category_id'] = f.categoryId;
      if (f.sourceKind == 'asset') {
        base['asset_id'] = f.sourceId;
        base['amount'] = _j(n(f.sourceAmount));
        base['price_toman'] = _j(n(f.priceToman));
        base['usd_rate'] = _j(n(f.usdRate));
      }
  }
  final snap = computeAmountSnapshots(f, wallets, rates, fallbackUsd);
  base['amount_toman_at_time'] = snap.toman == null ? null : _j(snap.toman!);
  base['amount_usd_at_time'] = snap.usd == null ? null : _j(snap.usd!);
  return base;
}

List<Json> buildTradeSnapshots(List<Transaction> txs, String userId) {
  final out = <Json>[];
  for (final tx in txs) {
    if (tx.type != 'BUY' && tx.type != 'SELL' && tx.type != 'TRANSFER') continue;
    final assetId = tx.assetId ??
        (tx.type == 'BUY' ? tx.targetAssetId : (tx.type == 'SELL' ? tx.sourceAssetId : (tx.sourceAssetId ?? tx.targetAssetId)));
    if (assetId == null || tx.dateString.isEmpty) continue;
    if (!RegExp(r'^[0-9]{4}/[0-9]{2}/[0-9]{2}$').hasMatch(tx.dateString)) continue;
    final p = tx.priceToman ?? 0;
    final r = tx.usdRate ?? 0;
    if (!_okPos(p) || !_okPos(r)) continue;
    out.add({'user_id': userId, 'asset_id': assetId, 'date_string': tx.dateString, 'price_toman': p, 'price_usd': p / r, 'source': 'trade'});
  }
  return out;
}

String usdRateAfterDateChange(TxForm prev, String nextDate, double Function(String) suggest) {
  final old = suggest(prev.date);
  final current = n(prev.usdRate);
  final untouched = prev.usdRate.isEmpty || !current.isFinite || (old > 0 && (current - old).abs() <= old * 1e-9);
  if (!untouched) return prev.usdRate;
  final nx = suggest(nextDate);
  return nx > 0 ? canonicalNumber(nx) : prev.usdRate;
}

String _fmtSummary(double v, Asset? a) {
  if (!_okPos(v)) return '—';
  if (a != null) return formatAssetAmount(v, a.decimalPlaces);
  return formatEnNumber(v, maxFrac: 6);
}

String summarizeForm(TxForm f, List<Wallet> wallets, List<Asset> assets, List<Category> categories, List<Person> persons) {
  String? nameOf(String? kind, String? id) {
    if (id == null) return null;
    if (kind == 'wallet') return _findWallet(wallets, id)?.name;
    if (kind == 'asset') return findAsset(assets, id)?.name;
    if (kind == 'person') {
      for (final p in persons) {
        if (p.id == id) return p.name;
      }
    }
    return null;
  }

  final sn = nameOf(f.sourceKind, f.sourceId) ?? '...';
  final tn = nameOf(f.targetKind, f.targetId) ?? '...';
  final sa = f.sourceKind == 'asset' ? findAsset(assets, f.sourceId) : null;
  final ta = f.targetKind == 'asset' ? findAsset(assets, f.targetId) : null;
  Category? cat;
  for (final c in categories) {
    if (c.id == f.categoryId) cat = c;
  }
  final label = kTypeStyles[f.type]!.label;
  final s = _fmtSummary(n(f.sourceAmount), sa);
  final t = _fmtSummary(n(f.targetAmount), ta);
  switch (f.type) {
    case 'BUY':
      return '$label · $t ${nameOf(f.targetKind, f.targetId) ?? '...'} از ${nameOf(f.sourceKind, f.sourceId) ?? '...'}';
    case 'SELL':
      return '$label · $s $sn → $tn';
    case 'TRANSFER':
      return '$label · $s از $sn به $tn';
    case 'INCOME':
      return '$label · $t → $tn${cat != null ? ' · ${cat.name}' : ''}';
    default:
      return '$label · $s از $sn${cat != null ? ' · ${cat.name}' : ''}';
  }
}

// ─── Convert ────────────────────────────────────────────────────────────────

class ConvertForm {
  String date = todayStr();
  String note = '';
  String? sourceAssetId;
  String sourceAmount = '';
  String sellPriceToman = '';
  String sellUsdRate = '';
  String? sellTargetWalletId;
  String? targetAssetId;
  String targetAmount = '';
  String buyPriceToman = '';
  String buyUsdRate = '';
  String? buySourceWalletId;
  bool matchBuyValue = true;
  String? operationId;
  String? sellTransactionId;
  String? buyTransactionId;

  ConvertForm copy() => ConvertForm()
    ..date = date
    ..note = note
    ..sourceAssetId = sourceAssetId
    ..sourceAmount = sourceAmount
    ..sellPriceToman = sellPriceToman
    ..sellUsdRate = sellUsdRate
    ..sellTargetWalletId = sellTargetWalletId
    ..targetAssetId = targetAssetId
    ..targetAmount = targetAmount
    ..buyPriceToman = buyPriceToman
    ..buyUsdRate = buyUsdRate
    ..buySourceWalletId = buySourceWalletId
    ..matchBuyValue = matchBuyValue
    ..operationId = operationId
    ..sellTransactionId = sellTransactionId
    ..buyTransactionId = buyTransactionId;
}

class ConvertPair {
  final Transaction sell, buy;
  ConvertPair(this.sell, this.buy);
}

ConvertForm buildInitialConvertForm(List<Asset> assets, double usdRate,
    {String? assetId, String? targetAssetId, String? sourceAmount, String? targetAmount, ConvertPair? pair}) {
  final f = ConvertForm();
  if (pair != null) {
    f.date = latinizeDigits(pair.sell.dateString);
    f.note = (pair.sell.note ?? '').replaceFirst(RegExp(r'^\[CONVERT\]\s*'), '').trim();
    f.sourceAssetId = pair.sell.sourceAssetId;
    f.sourceAmount = pair.sell.sourceAmount != null ? jsNumStr(pair.sell.sourceAmount) : '';
    f.sellPriceToman = pair.sell.priceToman != null ? jsNumStr(pair.sell.priceToman) : '';
    f.sellUsdRate = pair.sell.usdRate != null ? jsNumStr(pair.sell.usdRate) : jsNumStr(usdRate);
    f.sellTargetWalletId = pair.sell.targetWalletId;
    f.targetAssetId = pair.buy.targetAssetId;
    f.targetAmount = pair.buy.targetAmount != null ? jsNumStr(pair.buy.targetAmount) : '';
    f.buyPriceToman = pair.buy.priceToman != null ? jsNumStr(pair.buy.priceToman) : '';
    f.buyUsdRate = pair.buy.usdRate != null ? jsNumStr(pair.buy.usdRate) : jsNumStr(usdRate);
    f.buySourceWalletId = pair.buy.sourceWalletId;
    f.matchBuyValue = false;
    f.operationId = pair.sell.operationId ?? pair.buy.operationId;
    f.sellTransactionId = pair.sell.id;
    f.buyTransactionId = pair.buy.id;
    return f;
  }
  final sa = findAsset(assets, assetId);
  final ta = findAsset(assets, targetAssetId);
  f.sourceAssetId = assetId;
  f.sourceAmount = sourceAmount ?? '';
  f.sellPriceToman = sa != null ? jsNumStr(sa.priceToman) : '';
  f.sellUsdRate = jsNumStr(usdRate);
  f.targetAssetId = targetAssetId;
  f.targetAmount = targetAmount ?? '';
  f.buyPriceToman = ta != null ? jsNumStr(ta.priceToman) : '';
  f.buyUsdRate = jsNumStr(usdRate);
  return f;
}

ConvertForm applyMatchBuyValue(ConvertForm f) {
  if (!f.matchBuyValue) return f;
  final sq = n(f.sourceAmount), bq = n(f.targetAmount), sp = n(f.sellPriceToman);
  if (!(sq > 0) || !(bq > 0) || !(sp > 0)) return f;
  return f.copy()
    ..buyPriceToman = canonicalNumber((sq * sp) / bq)
    ..buyUsdRate = f.sellUsdRate.isNotEmpty ? f.sellUsdRate : f.buyUsdRate;
}

String? validateConvertForm(ConvertForm f, List<Transaction> txs, List<Wallet> wallets) {
  if (f.date.isEmpty) return 'تاریخ الزامی است.';
  if (parseJalaali(f.date) == null) return 'تاریخ نامعتبر است.';
  if (f.sourceAssetId == null) return 'دارایی مبدأ را انتخاب کن.';
  if (f.targetAssetId == null) return 'دارایی مقصد را انتخاب کن.';
  if (f.sourceAssetId == f.targetAssetId) return 'مبدأ و مقصد نباید یک دارایی باشند.';
  final sq = n(f.sourceAmount);
  if (!_okPos(sq)) return 'مقدار فروش نامعتبر است.';
  if (!_okPos(n(f.targetAmount))) return 'مقدار خرید نامعتبر است.';
  if (!_okPos(n(f.sellPriceToman))) return 'قیمت فروش هر واحد (تومان) نامعتبر است.';
  if (!_okPos(n(f.buyPriceToman))) return 'قیمت خرید هر واحد (تومان) نامعتبر است.';
  if (!_okPos(n(f.sellUsdRate))) return 'نرخ دلار فروش نامعتبر است.';
  if (!_okPos(n(f.buyUsdRate))) return 'نرخ دلار خرید نامعتبر است.';
  final holding = assetHolding(f.sourceAssetId!, txs);
  var editing = 0.0;
  if (f.sellTransactionId != null) {
    for (final t in txs) {
      if (t.id == f.sellTransactionId) editing = t.sourceAmount ?? 0;
    }
  }
  if (sq > holding + editing + 1e-9) return 'موجودی دارایی مبدأ کافی نیست.';
  if (f.sellTargetWalletId != null && !wallets.any((w) => w.id == f.sellTargetWalletId)) return 'کیف پول مقصد فروش نامعتبر است.';
  if (f.buySourceWalletId != null && !wallets.any((w) => w.id == f.buySourceWalletId)) return 'کیف پول مبدأ خرید نامعتبر است.';
  return null;
}

String? convertValueWarning(ConvertForm f) {
  final sq = n(f.sourceAmount), bq = n(f.targetAmount), sp = n(f.sellPriceToman), bp = n(f.buyPriceToman);
  if (!(sq > 0) || !(bq > 0) || !(sp > 0) || !(bp > 0)) return null;
  final st = sq * sp, bt = bq * bp;
  if ((st - bt).abs() <= math.max(st, bt) * 0.02) return null;
  return 'ارزش فروش و خرید اختلاف قابل توجهی دارد.';
}

String _deriveWalletAmount(double qty, double price, Wallet? w, List<CurrencyRate> rates, double fallbackUsd, String usd) {
  if (w == null || !(qty > 0) || !(price > 0)) return '';
  final r = walletRateForTransfer(w, rates, fallbackUsd, usd);
  if (!(r > 0)) return '';
  return canonicalNumber((qty * price) / r);
}

Snap _legSnap(double amount, double price, double usd) {
  if (!_okPos(amount) || !_okPos(price)) return Snap.none;
  final t = amount * price;
  return Snap(t, _okPos(usd) ? t / usd : null);
}

(Json, Json) buildConvertPayloads(ConvertForm f, String userId, List<Wallet> wallets, List<CurrencyRate> rates, double fallbackUsd, String operationId) {
  final trimmed = f.note.trim();
  final note = trimmed.isEmpty ? kConvertNotePrefix : '$kConvertNotePrefix $trimmed';
  final sq = n(f.sourceAmount), bq = n(f.targetAmount);
  final sp = n(f.sellPriceToman), su = n(f.sellUsdRate), bp = n(f.buyPriceToman), bu = n(f.buyUsdRate);
  final sw = f.sellTargetWalletId != null ? _findWallet(wallets, f.sellTargetWalletId) : null;
  final bw = f.buySourceWalletId != null ? _findWallet(wallets, f.buySourceWalletId) : null;
  final swa = _deriveWalletAmount(sq, sp, sw, rates, fallbackUsd, f.sellUsdRate);
  final bwa = _deriveWalletAmount(bq, bp, bw, rates, fallbackUsd, f.buyUsdRate);
  final ss = _legSnap(sq, sp, su), bs = _legSnap(bq, bp, bu);
  double? orNull(String s) {
    final v = n(s);
    return v.isFinite && v != 0 ? v : null;
  }

  final sell = <String, dynamic>{
    'user_id': userId,
    'type': 'SELL',
    'date_string': f.date,
    'note': note,
    'operation_id': operationId,
    'source_wallet_id': null,
    'source_asset_id': f.sourceAssetId,
    'source_person_id': null,
    'target_wallet_id': f.sellTargetWalletId,
    'target_asset_id': null,
    'target_person_id': null,
    'source_amount': sq,
    'target_amount': sw != null ? orNull(swa) : null,
    'category_id': null,
    'asset_id': f.sourceAssetId,
    'amount': sq,
    'price_toman': sp,
    'usd_rate': su,
    'amount_toman_at_time': ss.toman,
    'amount_usd_at_time': ss.usd,
  };
  final buy = <String, dynamic>{
    'user_id': userId,
    'type': 'BUY',
    'date_string': f.date,
    'note': note,
    'operation_id': operationId,
    'source_wallet_id': f.buySourceWalletId,
    'source_asset_id': null,
    'source_person_id': null,
    'target_wallet_id': null,
    'target_asset_id': f.targetAssetId,
    'target_person_id': null,
    'source_amount': bw != null ? orNull(bwa) : null,
    'target_amount': bq,
    'category_id': null,
    'asset_id': f.targetAssetId,
    'amount': bq,
    'price_toman': bp,
    'usd_rate': bu,
    'amount_toman_at_time': bs.toman,
    'amount_usd_at_time': bs.usd,
  };
  return (sell, buy);
}

Transaction? findConvertPartner(Transaction tx, List<Transaction> txs) {
  if (tx.operationId == null) return null;
  for (final r in txs) {
    if (r.id != tx.id && r.operationId == tx.operationId && r.type != tx.type && (r.type == 'BUY' || r.type == 'SELL')) return r;
  }
  return null;
}

bool isConvertTransaction(Transaction tx, List<Transaction> txs) {
  if (tx.operationId != null && findConvertPartner(tx, txs) != null) return true;
  return (tx.note ?? '').startsWith(kConvertNotePrefix);
}

ConvertPair? resolveConvertPair(Transaction tx, List<Transaction> txs) {
  final partner = findConvertPartner(tx, txs);
  if (partner != null) {
    final sell = tx.type == 'SELL' ? tx : partner;
    final buy = tx.type == 'BUY' ? tx : partner;
    if (sell.type == 'SELL' && buy.type == 'BUY') return ConvertPair(sell, buy);
  }
  if (!(tx.note ?? '').startsWith(kConvertNotePrefix)) return null;
  Transaction? fb;
  for (final r in txs) {
    if (r.id != tx.id && r.dateString == tx.dateString && (r.note ?? '').startsWith(kConvertNotePrefix) && r.type != tx.type) {
      fb = r;
      break;
    }
  }
  if (fb == null) return null;
  final sell = tx.type == 'SELL' ? tx : fb;
  final buy = tx.type == 'BUY' ? tx : fb;
  if (sell.type == 'SELL' && buy.type == 'BUY') return ConvertPair(sell, buy);
  return null;
}

class ConvertGroup {
  final String operationId;
  final Transaction sell, buy;
  ConvertGroup(this.operationId, this.sell, this.buy);
}

List<ConvertGroup> groupConvertTransactions(List<Transaction> txs) {
  final groups = <String, ConvertGroup>{};
  for (final tx in txs) {
    if (tx.type != 'SELL' && tx.type != 'BUY') continue;
    final pair = resolveConvertPair(tx, txs);
    if (pair == null) continue;
    final key = pair.sell.operationId ?? pair.buy.operationId ?? '${pair.sell.id}|${pair.buy.id}';
    groups.putIfAbsent(key, () => ConvertGroup(key, pair.sell, pair.buy));
  }
  return groups.values.toList();
}

Set<String> transactionIdsInConvertGroups(List<Transaction> txs) {
  final ids = <String>{};
  for (final g in groupConvertTransactions(txs)) {
    ids
      ..add(g.sell.id)
      ..add(g.buy.id);
  }
  return ids;
}
