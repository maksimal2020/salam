import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Ошибка обращения к серверу. status == 0 — нет связи.
class ApiError implements Exception {
  ApiError(this.status, this.code, [this.data]);
  final int status;
  final String code;
  final dynamic data;

  bool get isNetwork => status == 0;

  @override
  String toString() => 'ApiError($status, $code)';
}

/// Где хранится токен входа. В приложении — защищённое хранилище, в тестах — память.
abstract class TokenStore {
  Future<String?> read();
  Future<void> write(String? token);
}

class MemoryTokenStore implements TokenStore {
  String? _token;
  @override
  Future<String?> read() async => _token;
  @override
  Future<void> write(String? token) async => _token = token;
}

class ApiClient {
  ApiClient({
    required this.baseUrl,
    required this.tokens,
    required this.prefs,
    http.Client? client,
    this.onServedFromCache,
    this.onOnline,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final TokenStore tokens;
  final SharedPreferences prefs;
  final http.Client _client;
  final Duration timeout;

  /// Вызывается, когда ответ взят из сохранённой копии (нет связи).
  final void Function()? onServedFromCache;

  /// Вызывается после любого успешного ответа сервера.
  final void Function()? onOnline;

  Uri uri(String path, [Map<String, Object?>? query]) {
    final q = <String, String>{};
    query?.forEach((k, v) {
      if (v == null || v == false || v == '') return;
      q[k] = v.toString();
    });
    final base = Uri.parse(baseUrl);
    final prefix = base.path.replaceAll(RegExp(r'/+$'), '');
    return base.replace(path: '$prefix/api$path', queryParameters: q.isEmpty ? null : q);
  }

  /// [cache] — сохранять успешный ответ и отдавать его, если связи нет.
  /// Включать только для общих справочных данных, не для личных.
  Future<dynamic> get(String path, {Map<String, Object?>? query, bool cache = false}) =>
      _call('GET', uri(path, query), null, cache);

  Future<dynamic> post(String path, Object? body, {bool cache = false}) => _call('POST', uri(path), body ?? <String, dynamic>{}, cache);

  Future<dynamic> patch(String path, Object? body) => _call('PATCH', uri(path), body ?? <String, dynamic>{}, false);

  Future<dynamic> _call(String method, Uri u, Object? body, bool cache) async {
    final cacheKey = 'cache:$method $u ${body == null ? '' : jsonEncode(body)}';
    try {
      final data = await _send(method, u, body);
      onOnline?.call();
      if (cache) {
        // Ошибка записи в хранилище не должна ломать экран.
        try {
          await prefs.setString(cacheKey, jsonEncode(data));
        } catch (_) {}
      }
      return data;
    } on ApiError catch (e) {
      if (e.isNetwork && cache) {
        final saved = prefs.getString(cacheKey);
        if (saved != null) {
          onServedFromCache?.call();
          return jsonDecode(saved);
        }
      }
      rethrow;
    }
  }

  Future<dynamic> _send(String method, Uri u, Object? body) async {
    final headers = <String, String>{'accept': 'application/json'};
    if (body != null) headers['content-type'] = 'application/json';
    final token = await tokens.read();
    if (token != null && token.isNotEmpty) headers['authorization'] = 'Bearer $token';

    final res = await _request(method, u, headers, body);

    dynamic data;
    try {
      // Тело читаем как UTF-8 явно: иначе кириллица может испортиться.
      final text = utf8.decode(res.bodyBytes);
      data = text.isEmpty ? null : jsonDecode(text);
    } catch (_) {
      data = null;
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final code = data is Map && data['code'] is String ? data['code'] as String : 'server_error';
      throw ApiError(res.statusCode, code, data);
    }
    return data;
  }

  Future<http.Response> _request(String method, Uri u, Map<String, String> headers, Object? body) async {
    try {
      final encoded = body == null ? null : jsonEncode(body);
      if (method == 'POST') return await _client.post(u, headers: headers, body: encoded).timeout(timeout);
      if (method == 'PATCH') return await _client.patch(u, headers: headers, body: encoded).timeout(timeout);
      return await _client.get(u, headers: headers).timeout(timeout);
    } catch (_) {
      // SocketException, ClientException, TimeoutException — для пользователя это одно: нет связи.
      throw ApiError(0, 'network');
    }
  }

  void close() => _client.close();
}
