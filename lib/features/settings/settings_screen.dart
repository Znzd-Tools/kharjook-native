// Ports of SettingsTab.tsx, TelegramConnectionSection.tsx,
// NotificationSettingsSection.tsx and PasskeySettingsSection.tsx (list and
// delete only: passkey registration is bound to the web origin).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/models.dart';
import '../../core/services/api.dart';
import '../../core/store.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/toast.dart';
import '../../core/ui/widgets.dart';
import '../../core/utils/digits.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<PortfolioStore>();
    final user = s.user;
    if (user == null) return const SizedBox.shrink();
    final email = user.email ?? '';
    final phone = email.isNotEmpty ? email.split('@').first : (user.phone ?? '');
    return SubPage(
      title: 'تنظیمات',
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
        AppCard(
          child: Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: C.purple500.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.person_outline, color: C.purple400),
            ),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('اکانت', style: TextStyle(fontSize: 12, color: C.slate400)),
              Text(latinizeDigits(phone), textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
            ]),
          ]),
        ),
        const SizedBox(height: 12),
        const _TelegramSection(),
        const SizedBox(height: 12),
        const _PasskeySection(),
        const SizedBox(height: 12),
        const _NotificationSection(),
        const SizedBox(height: 12),
        AppCard(
          onTap: () async {
            Navigator.of(context).popUntil((r) => r.isFirst);
            await s.logout();
          },
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: C.rose.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.logout, size: 20, color: C.rose400),
            ),
            const SizedBox(width: 12),
            const Text('خروج از حساب', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: C.rose300)),
          ]),
        ),
      ]),
    );
  }
}

Widget _sectionHeader(IconData icon, Color color, String title, String subtitle, {Widget? trailing}) => Row(children: [
      Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, size: 20, color: color),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
          Text(subtitle, style: const TextStyle(fontSize: 11, color: C.slate500)),
        ]),
      ),
      ?trailing,
    ]);

// ─── Telegram ───────────────────────────────────────────────────────────────

class _TelegramSection extends StatefulWidget {
  const _TelegramSection();
  @override
  State<_TelegramSection> createState() => _TelegramSectionState();
}

class _TelegramSectionState extends State<_TelegramSection> {
  Json? connection;
  String? linkUrl;
  bool loading = true, busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final (status, body) = await Api.get('/api/telegram/connection');
      if (status < 200 || status >= 300) throw Exception('load failed');
      connection = body['connection'] as Json?;
    } catch (_) {
      Toast.error('خطا در دریافت وضعیت تلگرام.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _connect() async {
    setState(() => busy = true);
    try {
      final (status, body) = await Api.post('/api/telegram/link');
      final url = body['linkUrl'] as String?;
      if (status < 200 || status >= 300 || url == null) throw Exception((body['error'] as String?) ?? 'link failed');
      setState(() => linkUrl = url);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      Toast.success('لینک اتصال ساخته شد. در تلگرام «Start» را بزنید.');
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      Toast.error(msg.isNotEmpty ? msg : 'خطا در ساخت لینک.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _disconnect() async {
    setState(() => busy = true);
    try {
      final (status, _) = await Api.post('/api/telegram/connection');
      if (status < 200 || status >= 300) throw Exception('disconnect failed');
      setState(() {
        connection = null;
        linkUrl = null;
      });
      Toast.success('اتصال تلگرام قطع شد.');
    } catch (_) {
      Toast.error('خطا در قطع اتصال.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = connection != null && connection!['is_active'] != false;
    final username = connection?['telegram_username'] as String?;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _sectionHeader(Icons.link, C.sky400, 'تلگرام', 'دریافت گزارش و یادآور اقساط'),
        const SizedBox(height: 12),
        if (loading)
          const Text('در حال بارگذاری...', style: TextStyle(fontSize: 12, color: C.slate500))
        else if (connected) ...[
          Row(children: [
            const Text('✅ متصل', style: TextStyle(fontSize: 13, color: C.emerald300)),
            if ((username ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(right: 6), child: Text('@$username', textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 12, color: C.slate400))),
          ]),
          const SizedBox(height: 10),
          AppButton('قطع اتصال', icon: Icons.link_off, variant: BtnVariant.danger, expand: true, onPressed: busy ? null : _disconnect),
        ] else ...[
          const Text('برای دریافت پیام‌های خصوصی، ربات را در تلگرام فعال کنید.', style: TextStyle(fontSize: 12, color: C.slate400)),
          const SizedBox(height: 10),
          AppButton('اتصال تلگرام', icon: Icons.open_in_new, expand: true, onPressed: busy ? null : _connect),
          if (linkUrl != null) Padding(padding: const EdgeInsets.only(top: 8), child: SelectableText(linkUrl!, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 10, color: C.slate500))),
        ],
      ]),
    );
  }
}

// ─── Notifications ──────────────────────────────────────────────────────────

class _ToggleMeta {
  final String title, subtitle, activeLabel, description;
  final IconData icon;
  final Color accent;
  const _ToggleMeta(this.title, this.subtitle, this.activeLabel, this.icon, this.accent, this.description);
}

const _toggleMeta = {
  'enabled': _ToggleMeta('یادآور بدهی', 'فقط قسط‌های سررسید امروز', 'قسط‌های امروز — ۹:۰۰ صبح', Icons.event_available, C.amber,
      'هر روز ساعت ۹ صبح (وقت تهران)، اگر قسطی برای امروز شمسی داشته باشید، در تلگرام پیام می‌گیرید.'),
  'price_alert_enabled': _ToggleMeta('هشدار تغییر قیمت', 'پس از به‌روزرسانی قیمت‌ها در بات', 'فعال — هنگام رفرش قیمت', Icons.trending_up, C.sky400,
      'وقتی در بات تلگرام «به‌روزرسانی قیمت‌ها» را بزنید، در صورت تغییر معنادار، پیام دریافت می‌کنید.'),
  'expense_alert_enabled': _ToggleMeta('هشدار ثبت هزینه', 'بلافاصله پس از ثبت هزینه', 'فعال — هر هزینه جدید', Icons.receipt_outlined, C.rose,
      'با ثبت هر هزینه (در اپ یا بات)، مبلغ و جمع هزینه امروز در تلگرام ارسال می‌شود.'),
  'report_enabled': _ToggleMeta('گزارش خودکار', 'درآمد/هزینه و ارزش پرتفوی', 'فعال — ۹:۰۰ صبح', Icons.mail_outline, C.violet,
      'هر روز ساعت ۹ صبح (وقت تهران) خلاصه درآمد/هزینه امروز و ارزش پرتفوی در تلگرام ارسال می‌شود.'),
};

class _NotificationSection extends StatefulWidget {
  const _NotificationSection();
  @override
  State<_NotificationSection> createState() => _NotificationSectionState();
}

class _NotificationSectionState extends State<_NotificationSection> {
  Json? settings;
  bool loading = true;
  String? savingKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final (status, body) = await Api.get('/api/notifications/settings');
      if (status < 200 || status >= 300) throw Exception('load failed');
      settings = body['settings'] as Json?;
    } catch (_) {
      Toast.error('خطا در دریافت تنظیمات.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _patch(String key, Object value) async {
    final prev = settings;
    if (prev == null) return;
    setState(() {
      settings = {...prev, key: value};
      savingKey = key;
    });
    try {
      final (status, body) = await Api.put('/api/notifications/settings', {key: value});
      if (status < 200 || status >= 300) throw Exception('save failed');
      setState(() => settings = body['settings'] as Json? ?? settings);
      if (key == 'report_interval') {
        Toast.success(value == 'weekly' ? 'گزارش هفتگی فعال شد.' : 'گزارش روزانه فعال شد.');
      } else {
        final t = _toggleMeta[key]!.title;
        Toast.success(value == true ? '$t فعال شد.' : '$t خاموش شد.');
      }
    } catch (_) {
      Toast.error('خطا در ذخیره.');
      setState(() => settings = prev);
      _load();
    } finally {
      if (mounted) setState(() => savingKey = null);
    }
  }

  Widget _toggle(String key, bool checked) {
    final m = _toggleMeta[key]!;
    final disabled = savingKey != null;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: C.inset, borderRadius: BorderRadius.circular(18), border: Border.all(color: C.borderSoft)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: checked ? m.accent.withValues(alpha: 0.15) : C.white5,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: checked ? m.accent.withValues(alpha: 0.3) : C.white10),
            ),
            child: Icon(checked ? m.icon : Icons.notifications_off_outlined, size: 20, color: checked ? m.accent : C.slate500),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
              Text(m.subtitle, style: const TextStyle(fontSize: 11, color: C.slate500)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: checked ? C.emerald.withValues(alpha: 0.1) : C.white5,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: checked ? C.emerald.withValues(alpha: 0.25) : C.white10),
            ),
            child: Text(checked ? 'فعال' : 'خاموش', style: TextStyle(fontSize: 11, color: checked ? C.emerald300 : C.slate500)),
          ),
        ]),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(m.icon, size: 16, color: m.accent),
          const SizedBox(width: 8),
          Expanded(child: Text(m.description, style: const TextStyle(fontSize: 11, color: C.slate400, height: 1.6))),
        ]),
        const SizedBox(height: 10),
        Opacity(
          opacity: disabled ? 0.5 : 1,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: disabled ? null : () => _patch(key, !checked),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: checked ? m.accent.withValues(alpha: 0.1) : C.background,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: checked ? m.accent.withValues(alpha: 0.25) : C.borderSoft),
              ),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('یادآوری خودکار در تلگرام', style: TextStyle(fontSize: 12, color: C.slate200)),
                    Text(checked ? m.activeLabel : 'غیرفعال', style: const TextStyle(fontSize: 11, color: C.slate500)),
                  ]),
                ),
                Switch(value: checked, activeTrackColor: m.accent, onChanged: disabled ? null : (v) => _patch(key, v)),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = settings;
    if (loading || st == null) {
      return const AppCard(child: Text('در حال بارگذاری...', style: TextStyle(fontSize: 12, color: C.slate500)));
    }
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _sectionHeader(Icons.notifications_outlined, C.purple400, 'اعلان‌های تلگرام', 'هر گزینه مستقل از بقیه قابل تنظیم است'),
        for (final key in ['enabled', 'price_alert_enabled', 'expense_alert_enabled', 'report_enabled']) ...[
          _toggle(key, st[key] == true),
          if (key == 'report_enabled' && st['report_enabled'] == true)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('بازه ارسال گزارش', style: TextStyle(fontSize: 11, color: C.slate400)),
                const SizedBox(height: 6),
                Row(children: [
                  for (final iv in ['daily', 'weekly']) ...[
                    Expanded(
                      child: FilterChipX(
                        active: st['report_interval'] == iv,
                        label: iv == 'daily' ? 'روزانه' : 'هفتگی',
                        activeColor: C.violet,
                        onTap: savingKey != null ? () {} : () => _patch('report_interval', iv),
                      ),
                    ),
                    if (iv == 'daily') const SizedBox(width: 8),
                  ],
                ]),
              ]),
            ),
        ],
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: C.white5, borderRadius: BorderRadius.circular(14)),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.chat_bubble_outline, size: 14, color: C.slate400),
              SizedBox(width: 6),
              Expanded(child: Text('منوی بات: ثبت سریع، گزارش‌ها، قیمت‌ها، تنظیمات', style: TextStyle(fontSize: 11, color: C.slate300))),
            ]),
            SizedBox(height: 4),
            Text('اقساط معوق، موجودی کیف‌ها، ثبت درآمد/هزینه — از دکمه‌های بات در دسترس است.', style: TextStyle(fontSize: 11, color: C.slate500)),
          ]),
        ),
      ]),
    );
  }
}

// ─── Passkeys (list + delete) ───────────────────────────────────────────────

class _PasskeySection extends StatefulWidget {
  const _PasskeySection();
  @override
  State<_PasskeySection> createState() => _PasskeySectionState();
}

class _PasskeySectionState extends State<_PasskeySection> {
  List<Json> passkeys = [];
  bool loading = true, submitting = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<http.Response> _auth(String method, String path) {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    final uri = Uri.parse('${AppConfig.supabaseUrl}/auth/v1$path');
    final headers = {'apikey': AppConfig.supabaseAnonKey, 'Content-Type': 'application/json', if (token != null) 'Authorization': 'Bearer $token'};
    return (method == 'DELETE' ? http.delete(uri, headers: headers) : http.get(uri, headers: headers)).timeout(const Duration(seconds: 30));
  }

  Future<void> _refresh() async {
    setState(() => loading = true);
    try {
      if (Supabase.instance.client.auth.currentSession == null) {
        passkeys = [];
        return;
      }
      final r = await _auth('GET', '/passkeys');
      if (r.statusCode == 404) {
        passkeys = [];
        return;
      }
      if (r.statusCode < 200 || r.statusCode >= 300) throw Exception();
      final body = jsonDecode(utf8.decode(r.bodyBytes));
      final list = body is List ? body : (body is Map ? body['data'] as List? ?? const [] : const []);
      passkeys = list.cast<Json>();
    } catch (_) {
      passkeys = [];
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _delete(String id) async {
    setState(() => submitting = true);
    try {
      final r = await _auth('DELETE', '/passkeys/$id');
      if (r.statusCode < 200 || r.statusCode >= 300) throw Exception();
      Toast.success('کلید بیومتریک حذف شد.');
      await _refresh();
    } catch (_) {
      Toast.error('حذف کلید بیومتریک ناموفق بود.');
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _sectionHeader(Icons.fingerprint, C.emerald400, 'ورود بیومتریک', 'Face ID، Touch ID یا اثر انگشت'),
        const SizedBox(height: 10),
        if (loading)
          const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
        else if (passkeys.isEmpty)
          const Text('هنوز کلید بیومتریک ثبت نشده.', style: TextStyle(fontSize: 12, color: C.slate500))
        else
          for (final p in passkeys)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: C.white5, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(((p['friendly_name'] as String?) ?? '').trim().isNotEmpty ? (p['friendly_name'] as String).trim() : 'دستگاه ثبت‌شده', style: const TextStyle(fontSize: 12, color: C.slate200)),
                    if (p['last_used_at'] != null) Text('آخرین استفاده: ${p['last_used_at']}', textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 10, color: C.slate500)),
                  ]),
                ),
                IconButton(onPressed: submitting ? null : () => _delete(p['id'] as String), icon: const Icon(Icons.delete_outline, size: 16, color: C.rose300)),
              ]),
            ),
        const SizedBox(height: 6),
        const Text('افزودن کلید بیومتریک فقط از نسخه وب ممکن است. در اپ از ورود با رمز استفاده کن.', style: TextStyle(fontSize: 11, color: C.slate500, height: 1.6)),
      ]),
    );
  }
}
