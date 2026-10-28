// Port of EndpointSheetPicker.tsx.

import 'package:flutter/material.dart';

import '../../core/logic/ledger.dart';
import '../../core/models.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/widgets.dart';
import '../../core/utils/format.dart';
import 'tx_logic.dart';

const kWalletIconBg = Color(0x1FA855F7);
const kWalletIconFg = Color(0xFFC084FC);
const kAssetIconBg = Color(0x1FFBBF24);
const kAssetIconFg = Color(0xFFFBBF24);
const kPersonIconBg = Color(0x1F38BDF8);
const kPersonIconFg = Color(0xFF7DD3FC);

/// Returns (kind, id) or null.
Future<(String, String)?> showEndpointPicker(
  BuildContext context, {
  required String title,
  required List<String> allow,
  List<String> excludeIds = const [],
  required List<Wallet> wallets,
  required List<Asset> assets,
  required List<Person> persons,
  required List<Transaction> transactions,
}) {
  return showAppSheet<(String, String)>(
    context,
    title: title,
    scrollable: false,
    builder: (_) => _EndpointBody(
      allow: allow,
      exclude: excludeIds.where((e) => e.isNotEmpty).toSet(),
      wallets: wallets,
      assets: assets,
      persons: persons,
      transactions: transactions,
    ),
  );
}

class _EndpointBody extends StatefulWidget {
  final List<String> allow;
  final Set<String> exclude;
  final List<Wallet> wallets;
  final List<Asset> assets;
  final List<Person> persons;
  final List<Transaction> transactions;
  const _EndpointBody({required this.allow, required this.exclude, required this.wallets, required this.assets, required this.persons, required this.transactions});
  @override
  State<_EndpointBody> createState() => _EndpointBodyState();
}

class _EndpointBodyState extends State<_EndpointBody> {
  String q = '';
  late final Map<String, double> holdings = {
    if (widget.allow.contains('asset'))
      for (final a in widget.assets) a.id: assetHolding(a.id, widget.transactions)
  };
  late final Map<String, double> personBal = () {
    final m = <String, double>{};
    if (!widget.allow.contains('person')) return m;
    for (final tx in widget.transactions) {
      if (tx.targetPersonId != null) m[tx.targetPersonId!] = (m[tx.targetPersonId!] ?? 0) + numOr0(tx.targetAmount);
      if (tx.sourcePersonId != null) m[tx.sourcePersonId!] = (m[tx.sourcePersonId!] ?? 0) - numOr0(tx.sourceAmount);
    }
    return m;
  }();

  Widget _section(String label, String? empty, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8, right: 2),
            child: Text(label, style: const TextStyle(fontSize: 11, color: C.slate500, fontWeight: FontWeight.w700)),
          ),
          if (empty != null) Text(empty, style: const TextStyle(fontSize: 12, color: C.slate600)) else ...children,
        ]),
      );

  void _pick(String kind, String id) {
    haptic();
    Navigator.pop(context, (kind, id));
  }

  @override
  Widget build(BuildContext context) {
    final query = q.trim().toLowerCase();
    final ws = widget.allow.contains('wallet')
        ? widget.wallets
            .where((w) => !widget.exclude.contains(w.id))
            .where((w) => query.isEmpty || w.name.toLowerCase().contains(query) || w.currency.toLowerCase().contains(query))
            .toList()
        : <Wallet>[];
    final as = widget.allow.contains('asset')
        ? widget.assets
            .where((a) => !widget.exclude.contains(a.id))
            .where((a) => query.isEmpty || a.name.toLowerCase().contains(query) || a.unit.toLowerCase().contains(query))
            .toList()
        : <Asset>[];
    final ps = widget.allow.contains('person')
        ? widget.persons.where((p) => !widget.exclude.contains(p.id)).where((p) => query.isEmpty || p.name.toLowerCase().contains(query)).toList()
        : <Person>[];
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: AppTextField(value: q, onChanged: (v) => setState(() => q = v), hint: 'جستجو...', prefixIcon: const Icon(Icons.search, size: 18, color: C.slate500)),
      ),
      Flexible(
        child: ListView(shrinkWrap: true, children: [
          if (widget.allow.contains('wallet'))
            _section('کیف پول‌ها', ws.isEmpty ? 'کیف پولی یافت نشد.' : null, [
              for (final w in ws)
                PickRow(
                  label: w.name,
                  sublabel: '${currencyMeta(w.currency).symbol} ${w.currency}',
                  leading: EntityIcon(iconUrl: w.iconUrl, fallback: Icons.account_balance_wallet_outlined, bgColor: kWalletIconBg, color: kWalletIconFg, size: 36),
                  trailing: Money(formatCurrencyAmount(calculateWalletStats(w, widget.transactions).balance, w.currency),
                      style: const TextStyle(fontSize: 12, color: C.slate300)),
                  onTap: () => _pick('wallet', w.id),
                ),
            ]),
          if (widget.allow.contains('asset'))
            _section('دارایی‌ها', as.isEmpty ? 'دارایی‌ای یافت نشد.' : null, [
              for (final a in as)
                PickRow(
                  label: a.name,
                  sublabel: a.unit,
                  leading: EntityIcon(iconUrl: a.iconUrl, fallback: Icons.toll_outlined, bgColor: kAssetIconBg, color: kAssetIconFg, size: 36),
                  trailing: Money((holdings[a.id] ?? 0) > 0 ? formatAssetAmount(holdings[a.id], a.decimalPlaces) : '—',
                      style: const TextStyle(fontSize: 12, color: C.slate300)),
                  onTap: () => _pick('asset', a.id),
                ),
            ]),
          if (widget.allow.contains('person'))
            _section('اشخاص', ps.isEmpty ? 'شخصی یافت نشد.' : null, [
              for (final p in ps)
                Builder(builder: (_) {
                  final b = personBal[p.id] ?? 0;
                  final status = b > 0 ? 'بدهکار' : (b < 0 ? 'بستانکار' : 'تسویه');
                  final tone = b > 0 ? C.amber300 : (b < 0 ? C.cyan300 : C.slate500);
                  return PickRow(
                    label: p.name,
                    sublabel: 'وضعیت: $status',
                    leading: const EntityIcon(fallback: Icons.person_outline, bgColor: kPersonIconBg, color: kPersonIconFg, size: 36),
                    trailing: Money(formatEnNumber(b.abs(), maxFrac: 6), style: TextStyle(fontSize: 12, color: tone)),
                    onTap: () => _pick('person', p.id),
                  );
                }),
            ]),
        ]),
      ),
    ]);
  }
}
