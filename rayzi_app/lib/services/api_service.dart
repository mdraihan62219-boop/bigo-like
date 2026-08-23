import 'package:dio/dio.dart';
import '../config/constants.dart';
import 'session_events.dart';
import 'token_store.dart';

class ApiService {
  static final Dio _dio = Dio(BaseOptions(
    baseUrl: AppConstants.apiBaseUrl,
    connectTimeout: AppConstants.apiTimeout,
    receiveTimeout: AppConstants.apiTimeout,
    headers: {'Content-Type': 'application/json'},
  ));

  static void init() {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await TokenStore.read();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
        onError: (error, handler) async {
          if (error.response?.statusCode == 401) {
            // Session is no longer valid — drop the stored token and notify
            // the root navigator to bounce to login. Guests (no stored token
            // to begin with) never trigger the event.
            final hadToken = (await TokenStore.read())?.isNotEmpty == true;
            await TokenStore.clear();
            if (hadToken) SessionEvents.emitSessionExpired();
          }
          return handler.next(error);
        },
    ));
  }

  static Future<Response> get(String path, {Map<String, dynamic>? queryParameters}) {
    return _dio.get(path, queryParameters: queryParameters);
  }

  static Future<Response> post(String path, {dynamic data}) {
    return _dio.post(path, data: data);
  }

  static Future<Response> put(String path, {dynamic data}) {
    return _dio.put(path, data: data);
  }

  static Future<Response> delete(String path) {
    return _dio.delete(path);
  }
}
