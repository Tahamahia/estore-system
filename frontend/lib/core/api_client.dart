import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'auth_service.dart';

/// Base API configuration
const String kBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://127.0.0.1:8787/api/v1');

// Mirror the SharedPreferences key used by AuthService so the 401 interceptor
// can purge the stale token without importing auth_service internals.
const String _kTokenKey = 'auth_token';

/// Dio instance provider with auth interceptor
final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: kBaseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    headers: {'Content-Type': 'application/json'},
  ));

  // Auth interceptor: attaches JWT + Idempotency-Key
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) {
      final token = ref.read(authTokenProvider);
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }

      // Auto-generate idempotency key for mutations.
      // ??= only assigns when the key is absent — callers (e.g. createOrder)
      // can pre-set a stable key derived from the client-generated resource UUID
      // so that retries after a timeout reuse the same key.
      if (['POST', 'PUT', 'PATCH'].contains(options.method)) {
        options.headers['Idempotency-Key'] ??= const Uuid().v4();
      }
      handler.next(options);
    },
    onError: (error, handler) {
      if (error.response?.statusCode == 401) {
        // Clear in-memory token → GoRouter redirect fires to /login
        ref.read(authTokenProvider.notifier).state = null;
        // Also purge the persisted token so the expired JWT is not
        // reloaded from SharedPreferences on the next app launch.
        SharedPreferences.getInstance()
            .then((prefs) => prefs.remove(_kTokenKey));
      }
      // Extract the server's human-readable message from the response body so
      // all callers receive DioException.message = the actual error text rather
      // than the generic "status code of 4xx/5xx" Dio default.
      final body = error.response?.data;
      if (body is Map<String, dynamic>) {
        final serverMsg = body['message'] as String? ?? body['error'] as String?;
        if (serverMsg != null && serverMsg.isNotEmpty) {
          return handler.reject(DioException(
            requestOptions: error.requestOptions,
            response: error.response,
            type: error.type,
            error: error.error,
            message: serverMsg,
          ));
        }
      }
      handler.next(error);
    },
  ));

  return dio;
});
