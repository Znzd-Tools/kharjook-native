import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../models.dart';

/// Calls the web app's authenticated `/api/*` routes with the Supabase access
/// token as a Bearer header (cookies don't exist in the native app).
class Api {
  static Map<String, String> _headers() {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    return {
      'content-type': 'application/json',
      if (token != null) 'authorization': 'Bearer $token',
    };
  }

  static Uri _u(String path) => Uri.parse('${AppConfig.apiBaseUrl}$path');

  static Future<(int, Json)> get(String path) async {
    final r = await http.get(_u(path), headers: _headers()).timeout(const Duration(seconds: 30));
    return (r.statusCode, _decode(r));
  }

  static Future<(int, Json)> post(String path, [Object? body]) async {
    final r = await http.post(_u(path), headers: _headers(), body: body == null ? null : jsonEncode(body)).timeout(const Duration(seconds: 30));
    return (r.statusCode, _decode(r));
  }

  static Future<(int, Json)> put(String path, Object body) async {
    final r = await http.put(_u(path), headers: _headers(), body: jsonEncode(body)).timeout(const Duration(seconds: 30));
    return (r.statusCode, _decode(r));
  }

  static Json _decode(http.Response r) {
    try {
      final v = jsonDecode(utf8.decode(r.bodyBytes));
      return v is Map<String, dynamic> ? v : {'data': v};
    } catch (_) {
      return {};
    }
  }

  /// fire-expense-alert.ts — fire and forget.
  static void fireExpenseAlert(List<String> ids) {
    if (ids.isEmpty) return;
    post('/api/notifications/expense-alert', {'transactionIds': ids}).catchError((_) => (0, <String, dynamic>{}));
  }
}
