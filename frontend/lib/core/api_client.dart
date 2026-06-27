import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_service.dart';

/// Base API configuration
const String kBaseUrl = 'http://127.0.0.1:8787/api/v1';

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

      // Auto-generate idempotency key for mutations
      if (['POST', 'PUT', 'PATCH'].contains(options.method)) {
        options.headers['Idempotency-Key'] ??=
            '${DateTime.now().millisecondsSinceEpoch}-${options.path.hashCode}';
      }
      handler.next(options);
    },
    onError: (error, handler) {
      if (error.response?.statusCode == 401) {
        // Token expired — force re-login
        ref.read(authTokenProvider.notifier).state = null;
      }
      handler.next(error);
    },
  ));

  return dio;
});
