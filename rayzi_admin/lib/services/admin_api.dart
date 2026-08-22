import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// REST client for the Rayzi admin API.
///
/// The panel previously wrote directly to Supabase tables using the public
/// anon key — which its own RLS policies correctly rejected. All moderation
/// now flows through the backend's `/admin/*` endpoints, which enforce
/// `requireAdmin` against `profiles.role`.
class AdminApi {
  AdminApi._();

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000',
  );

  static final Dio _dio = Dio(BaseOptions(
    baseUrl: '$baseUrl/api/v1',
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    headers: {'Content-Type': 'application/json'},
  ));

  static const String _tokenKey = 'admin_jwt';
  static Map<String, dynamic>? _profile;

  static void init() {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _token();
        if (token != null) options.headers['Authorization'] = 'Bearer $token';
        return handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          await logout();
        }
        return handler.next(error);
      },
    ));
  }

  static Future<String?> _token() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  /// Returns the admin profile on success.
  /// Throws [ApiException] on invalid credentials or non-admin accounts.
  static Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final res = await _dio.post('/auth/login', data: {
        'email': email,
        'password': password,
      });
      final token = res.data['data']?['token'] as String?;
      if (token == null) throw ApiException('Login failed');

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);

      final me = await _dio.get('/auth/me');
      _profile = Map<String, dynamic>.from(me.data['data'] as Map);

      if (_profile?['role'] != 'admin') {
        await logout();
        throw ApiException('This account does not have admin access');
      }
      return _profile!;
    } on DioException catch (e) {
      final msg = e.response?.data?['error'] ?? e.message ?? 'Login failed';
      throw ApiException(msg.toString());
    }
  }

  static Future<void> logout() async {
    _profile = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  static bool get isProbablyAdmin => _profile?['role'] == 'admin';

  /// Verifies any stored token still belongs to an admin (used by the route
  /// guard on cold start).
  static Future<bool> restoreSession() async {
    if (await _token() == null) return false;
    try {
      final me = await _dio.get('/auth/me');
      _profile = Map<String, dynamic>.from(me.data['data'] as Map);
      return _profile?['role'] == 'admin';
    } catch (_) {
      await logout();
      return false;
    }
  }

  static Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    return _guard(() => _dio.get(path, queryParameters: query));
  }

  static Future<dynamic> post(String path, {Object? data}) async {
    return _guard(() => _dio.post(path, data: data));
  }

  static Future<dynamic> put(String path, {Object? data}) async {
    return _guard(() => _dio.put(path, data: data));
  }

  static Future<dynamic> delete(String path) async {
    return _guard(() => _dio.delete(path));
  }

  static dynamic _payload(Response res) => res.data['data'];

  static Future<dynamic> _guard(Future<Response> Function() fn) async {
    try {
      final res = await fn();
      return _payload(res);
    } on DioException catch (e) {
      debugPrint('AdminApi error [$e.requestOptions.path]: ${e.response?.data}');
      final msg = e.response?.data?['error'] ?? e.message ?? 'Request failed';
      throw ApiException(msg.toString());
    }
  }
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}
