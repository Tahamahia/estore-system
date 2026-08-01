import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';

/// SharedPreferences key for persisted JWT
const String _kAuthTokenKey = 'auth_token';
const String _kUserKey = 'auth_user';

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
      final token = data['token'] as String?;
      _ref.read(authTokenProvider.notifier).state = token;
      _ref.read(currentUserProvider.notifier).state = data['user'];

      // Persist token and user to SharedPreferences
      if (token != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kAuthTokenKey, token);
        await prefs.setString(_kUserKey, jsonEncode(data['user']));
      }

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

  Future<void> logout() async {
    _ref.read(authTokenProvider.notifier).state = null;
    _ref.read(currentUserProvider.notifier).state = null;

    // Clear persisted token and user
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAuthTokenKey);
    await prefs.remove(_kUserKey);
  }

  /// Load saved token and user from SharedPreferences on app start
  static Future<void> loadSavedToken(ProviderContainer container) async {
    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString(_kAuthTokenKey);
    if (savedToken != null && savedToken.isNotEmpty) {
      container.read(authTokenProvider.notifier).state = savedToken;
      final savedUser = prefs.getString(_kUserKey);
      if (savedUser != null && savedUser.isNotEmpty) {
        container.read(currentUserProvider.notifier).state =
            Map<String, dynamic>.from(jsonDecode(savedUser) as Map);
      }
    }
  }

  String _extractError(DioException e) {
    final data = e.response?.data;
    if (data is Map) return data['message'] ?? 'Request failed';
    return e.message ?? 'Network error';
  }
}

