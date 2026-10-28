// Ports of LoginView / RegisterView. Passkey (WebAuthn) login is web-only.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/widgets.dart';
import '../../main.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool register = false;
  bool justRegistered = false;
  @override
  Widget build(BuildContext context) => register
      ? RegisterScreen(onLogin: ({bool registered = false}) => setState(() {
            register = false;
            justRegistered = registered;
          }))
      : LoginScreen(justRegistered: justRegistered, onRegister: () => setState(() => register = true));
}

class _AuthFrame extends StatelessWidget {
  final String? subtitle;
  final List<Widget> children;
  const _AuthFrame({this.subtitle, required this.children});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: C.shell,
        body: Stack(children: [
          Positioned(top: -40, right: -40, child: _glow(C.purple500)),
          Positioned(bottom: -40, left: -40, child: _glow(const Color(0xFF3B82F6))),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Center(
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: C.purple500.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: C.purple500.withValues(alpha: 0.2)),
                      ),
                      child: const Icon(Icons.account_balance_wallet_outlined, size: 32, color: C.purple500),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('خرجوک', textAlign: TextAlign.center, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: Colors.white)),
                  if (subtitle != null) Text(subtitle!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: C.slate500)),
                  const SizedBox(height: 32),
                  ...children,
                ]),
              ),
            ),
          ),
        ]),
      );

  Widget _glow(Color c) => Container(
        width: 140,
        height: 140,
        decoration: BoxDecoration(shape: BoxShape.circle, color: c.withValues(alpha: 0.1), boxShadow: [BoxShadow(color: c.withValues(alpha: 0.15), blurRadius: 80, spreadRadius: 20)]),
      );
}

Widget _banner(String text, Color c) => Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: c.withValues(alpha: 0.2))),
      child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: c, fontSize: 12)),
    );

class LoginScreen extends StatefulWidget {
  final bool justRegistered;
  final VoidCallback onRegister;
  const LoginScreen({super.key, required this.justRegistered, required this.onRegister});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String email = '', password = '', error = '';
  bool submitting = false;

  Future<void> _login() async {
    if (email.isEmpty || password.isEmpty) return;
    setState(() {
      submitting = true;
      error = '';
    });
    try {
      await Supabase.instance.client.auth.signInWithPassword(email: email.trim(), password: password);
    } catch (_) {
      if (mounted) {
        setState(() {
          error = 'ایمیل یا رمز عبور اشتباه است.';
          submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => _AuthFrame(children: [
        if (widget.justRegistered && error.isEmpty) _banner('حساب با موفقیت ساخته شد. لطفاً وارد شو.', C.emerald400),
        if (error.isNotEmpty) _banner(error, C.rose400),
        Field(
          label: 'ایمیل',
          child: AppTextField(value: email, onChanged: (v) => email = v, ltr: true, keyboardType: TextInputType.emailAddress, prefixIcon: const Icon(Icons.person_outline, size: 18, color: C.slate500)),
        ),
        Field(
          label: 'رمز عبور',
          child: AppTextField(value: password, onChanged: (v) => password = v, ltr: true, obscure: true, prefixIcon: const Icon(Icons.lock_outline, size: 18, color: C.slate500)),
        ),
        const SizedBox(height: 10),
        AppButton('ورود به حساب', expand: true, loading: submitting, onPressed: _login),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('حساب نداری؟ ', style: TextStyle(fontSize: 12, color: C.slate500)),
          GestureDetector(onTap: widget.onRegister, child: const Text('ثبت‌نام', style: TextStyle(fontSize: 12, color: C.purple400, fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 20),
        Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SetupScreen(editing: true))),
            child: const Text('تنظیمات اتصال سرور', style: TextStyle(fontSize: 11, color: C.slate600)),
          ),
        ),
      ]);
}

class RegisterScreen extends StatefulWidget {
  final void Function({bool registered}) onLogin;
  const RegisterScreen({super.key, required this.onLogin});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  String email = '', password = '', confirm = '', error = '';
  bool submitting = false;

  String _map(String raw) {
    final m = raw.toLowerCase();
    if (m.contains('already registered') || m.contains('already exists')) return 'این ایمیل قبلاً ثبت شده است.';
    if (m.contains('invalid email')) return 'ایمیل وارد شده معتبر نیست.';
    if (m.contains('password')) return 'رمز عبور معتبر نیست.';
    return raw;
  }

  Future<void> _register() async {
    if (email.isEmpty || password.isEmpty) return;
    if (password.length < 6) {
      setState(() => error = 'رمز عبور باید حداقل 6 کاراکتر باشد.');
      return;
    }
    if (password != confirm) {
      setState(() => error = 'تکرار رمز عبور مطابقت ندارد.');
      return;
    }
    setState(() {
      submitting = true;
      error = '';
    });
    try {
      final res = await Supabase.instance.client.auth.signUp(email: email.trim(), password: password);
      if (res.session == null) widget.onLogin(registered: true);
    } on AuthException catch (e) {
      setState(() {
        error = _map(e.message);
        submitting = false;
      });
    } catch (e) {
      setState(() {
        error = '$e';
        submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => _AuthFrame(subtitle: 'ساخت حساب جدید', children: [
        if (error.isNotEmpty) _banner(error, C.rose400),
        Field(label: 'ایمیل', child: AppTextField(value: email, onChanged: (v) => email = v, ltr: true, keyboardType: TextInputType.emailAddress)),
        Field(label: 'رمز عبور', child: AppTextField(value: password, onChanged: (v) => password = v, ltr: true, obscure: true)),
        Field(label: 'تکرار رمز عبور', child: AppTextField(value: confirm, onChanged: (v) => confirm = v, ltr: true, obscure: true)),
        const SizedBox(height: 10),
        AppButton('ساخت حساب', expand: true, loading: submitting, onPressed: _register),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('حساب داری؟ ', style: TextStyle(fontSize: 12, color: C.slate500)),
          GestureDetector(onTap: () => widget.onLogin(), child: const Text('ورود', style: TextStyle(fontSize: 12, color: C.purple400, fontWeight: FontWeight.w600))),
        ]),
      ]);
}

/// First-run backend setup (only when the build has no --dart-define values).
class SetupScreen extends StatefulWidget {
  final bool editing;
  const SetupScreen({super.key, this.editing = false});
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late String url = AppConfig.supabaseUrl, key = AppConfig.supabaseAnonKey, api = AppConfig.apiBaseUrl;
  String error = '';

  Future<void> _save() async {
    if (!url.startsWith('https://') || key.length < 20) {
      setState(() => error = 'آدرس Supabase و کلید anon را درست وارد کن.');
      return;
    }
    await AppConfig.save(url: url, key: key, api: api);
    if (!mounted) return;
    if (widget.editing) {
      setState(() => error = 'ذخیره شد. برنامه را کامل ببند و دوباره باز کن.');
      return;
    }
    await Supabase.initialize(url: AppConfig.supabaseUrl, anonKey: AppConfig.supabaseAnonKey);
    runApp(const KharjookApp());
  }

  @override
  Widget build(BuildContext context) => _AuthFrame(subtitle: 'اتصال به سرور', children: [
        const Text('این نسخه بدون تنظیمات سرور ساخته شده. مقادیر را از تنظیمات پروژه Supabase (Project Settings → API) وارد کن. فقط یک بار لازم است.',
            style: TextStyle(fontSize: 12, color: C.slate400, height: 1.7)),
        const SizedBox(height: 16),
        if (error.isNotEmpty) _banner(error, C.amber300),
        Field(label: 'Supabase URL', child: AppTextField(value: url, onChanged: (v) => url = v.trim(), ltr: true, hint: 'https://xxxx.supabase.co')),
        Field(label: 'Supabase anon key', child: AppTextField(value: key, onChanged: (v) => key = v.trim(), ltr: true, maxLines: 3)),
        Field(label: 'آدرس وب‌اپ (برای قیمت‌ها و تلگرام)', child: AppTextField(value: api, onChanged: (v) => api = v.trim(), ltr: true)),
        AppButton('ذخیره و ادامه', expand: true, onPressed: _save),
      ]);
}
