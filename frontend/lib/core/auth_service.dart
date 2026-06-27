import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_client.dart';

/// Auth token state — persists the JWT
final authTokenProvider = StateProvider<String?>((ref) => null);

/// Current user data
final currentUserProvider = StateProvider<Map<String, dynamic>?>((ref) => null);

/// Auth service for login/register
final authServiceProvider = Provider((ref) => AuthService(ref));

class AuthService {
  final Ref _ref;
  AuthService(this._ref);

  Dio get _dio => _ref.read(dioProvider);

  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final response = await _dio.post('/auth/login', data: {
        'email': email,
        'password': password,
      });

      final data = response.data as Map<String, dynamic>;
      _ref.read(authTokenProvider.notifier).state = data['token'];
      _ref.read(currentUserProvider.notifier).state = data['user'];
      return data;
    } on DioException catch (e) {
      throw _extractError(e);
    }
  }

  Future<Map<String, dynamic>> register({
    required String id,
    required String email,
    required String password,
    required String fullName,
    required String tenantId,
    required String role,
  }) async {
    try {
      final response = await _dio.post('/auth/register', data: {
        'id': id,
        'email': email,
        'password': password,
        'full_name': fullName,
        'tenant_id': tenantId,
        'role': role,
      });
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _extractError(e);
    }
  }

  void logout() {
    _ref.read(authTokenProvider.notifier).state = null;
    _ref.read(currentUserProvider.notifier).state = null;
  }

  String _extractError(DioException e) {
    final data = e.response?.data;
    if (data is Map) return data['message'] ?? 'Request failed';
    return e.message ?? 'Network error';
  }
}
