// Port of WalletsTab.tsx.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/router.dart';
import '../../core/logic/ledger.dart';
import '../../core/store.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/widgets.dart';
import '../../core/utils/format.dart';
import '../transactions/endpoint_picker.dart';
import '../transactions/tx_logic.dart';

class WalletsTab extends StatelessWidget {
  const WalletsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<PortfolioStore>();
    final mode = s.currencyMode;
    final rows = s.wallets.map((w) {
      final st = calculateWalletStats(w, s.transactions);
      final r = walletRateNow(w.currency, s.currencyRates, s.rateHistories);
      return (w, st, st.balance * r.rate, r.rate);
    }).toList();
    final totalToman = rows.fold(0.0, (a, r) => a + r.$3);
    final display = mode == 'USD' ? (s.usdRate > 0 ? totalToman / s.usdRate : 0.0) : totalToman;
    final missing = rows.any((r) => r.$1.currency != 'IRT' && r.$4 == 0);
    return RefreshIndicator(
      onRefresh: s.refresh,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
        Row(children: [
          const Expanded(child: Text('کیف پول‌ها', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white))),
          IconBtn(Icons.tune, tooltip: 'مدیریت', onTap: () => Nav.push(context, '/manage/wallets')),
        ]),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: C.purple500.withValues(alpha: 0.2)),
            gradient: LinearGradient(colors: [C.purple.withValues(alpha: 0.2), C.raised], begin: Alignment.topRight, end: Alignment.bottomLeft),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('جمع کل نقد (تبدیل به ${mode == 'USD' ? 'دلار' : 'تومان'})', style: const TextStyle(fontSize: 12, color: C.slate400)),
            const SizedBox(height: 4),
            Money(formatCurrency(display, mode), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white)),
            if (missing)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                  const Text('برای برخی ارزها نرخ تبدیل تعریف نشده. از ', style: TextStyle(fontSize: 11, color: C.amber300)),
                  GestureDetector(
                    onTap: () => Nav.push(context, '/prices'),
                    child: const Text('قیمت‌ها و نرخ‌ها', style: TextStyle(fontSize: 11, color: C.purple300, decoration: TextDecoration.underline)),
                  ),
                  const Text(' مقدار را اضافه کن.', style: TextStyle(fontSize: 11, color: C.amber300)),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 14),
        if (s.isLoadingData && s.wallets.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
        if (!s.isLoadingData && s.wallets.isEmpty)
          EmptyState(
              icon: Icons.account_balance_wallet_outlined, title: 'هنوز کیف پولی نساخته‌ای.', actionLabel: 'افزودن کیف پول', onAction: () => Nav.push(context, '/manage/wallets')),
        for (final (w, st, bt, _) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppCard(
              padding: const EdgeInsets.all(14),
              onTap: () => Nav.push(context, '/wallets/${w.id}'),
              child: Row(children: [
                EntityIcon(iconUrl: w.iconUrl, fallback: Icons.account_balance_wallet_outlined, bgColor: const Color(0x1AA855F7), color: kWalletIconFg, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(w.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                    Money('${currencyMeta(w.currency).symbol} ${formatCurrencyAmount(st.balance, w.currency)} ${w.currency}', style: const TextStyle(fontSize: 12, color: C.slate400)),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Money(formatCurrency(mode == 'USD' && s.usdRate > 0 ? bt / s.usdRate : bt, mode), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                  if (st.incomeTotal > 0 || st.expenseTotal > 0)
                    Money('+${formatCurrencyAmount(st.incomeTotal, w.currency)} / -${formatCurrencyAmount(st.expenseTotal, w.currency)}', style: const TextStyle(fontSize: 10, color: C.slate500)),
                ]),
                const Icon(Icons.chevron_left, size: 18, color: C.slate500),
              ]),
            ),
          ),
      ]),
    );
  }
}
