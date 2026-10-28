import 'package:shared_preferences/shared_preferences.dart';

/// Backend settings. Values come from `--dart-define` at build time; when a
/// build has none, the app asks once on first launch and stores them.
class AppConfig {
  static const _defUrl = String.fromEnvironment('SUPABASE_URL');
  static const _defKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const _defApi = String.fromEnvironment('API_BASE_URL', defaultValue: 'https://kharjook.vercel.app');

  static String supabaseUrl = _defUrl;
  static String supabaseAnonKey = _defKey;
  static String apiBaseUrl = _defApi;

  static bool get isComplete => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    if (_defUrl.isEmpty) supabaseUrl = p.getString('cfg_supabase_url') ?? '';
    if (_defKey.isEmpty) supabaseAnonKey = p.getString('cfg_supabase_key') ?? '';
    apiBaseUrl = p.getString('cfg_api_base') ?? _defApi;
  }

  static Future<void> save({required String url, required String key, required String api}) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('cfg_supabase_url', url.trim());
    await p.setString('cfg_supabase_key', key.trim());
    await p.setString('cfg_api_base', api.trim());
    supabaseUrl = url.trim();
    supabaseAnonKey = key.trim();
    apiBaseUrl = api.trim().replaceAll(RegExp(r'/+$'), '');
  }
}
