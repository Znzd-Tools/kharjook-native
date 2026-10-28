// Port of DeadlinesTab.tsx.

import 'package:flutter/material.dart';

import '../../app/router.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/widgets.dart';

const _items = [
  ('اقساط و وام‌ها', 'مدیریت پرداخت‌های دوره‌ای و اقساط', Icons.event_note, '/deadlines/loans'),
  ('اشخاص', 'مدیریت طلب و بدهی اشخاص', Icons.handshake_outlined, '/deadlines/persons'),
  ('چک‌ها', 'ثبت و پیگیری چک‌های صادره', Icons.receipt_long_outlined, '/deadlines/checks'),
  ('اشتراک‌ها', 'مدیریت اشتراک‌های دوره‌ای', Icons.repeat, '/deadlines/subscriptions'),
];

class DeadlinesTab extends StatelessWidget {
  const DeadlinesTab({super.key});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
        const Text('سررسید', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
        const SizedBox(height: 14),
        for (final (title, sub, icon, href) in _items)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppCard(
              onTap: () => Nav.push(context, href),
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
                    Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: C.slate200)),
                    Text(sub, style: const TextStyle(fontSize: 11, color: C.slate500)),
                  ]),
                ),
                const Icon(Icons.chevron_left, size: 20, color: C.slate600),
              ]),
            ),
          ),
      ]);
}
