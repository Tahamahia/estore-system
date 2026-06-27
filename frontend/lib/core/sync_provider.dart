import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'api_client.dart';
import 'auth_service.dart';

/// Sync state model — lightweight counts and dirty flags
class SyncState {
  final DateTime serverTime;
  final bool dirty;
  final Map<String, dynamic> orders;
  final Map<String, dynamic> customers;
  final Map<String, dynamic> shipments;
  final Map<String, dynamic> orphans;

  const SyncState({
    required this.serverTime,
    required this.dirty,
    required this.orders,
    required this.customers,
    required this.shipments,
    required this.orphans,
  });

  factory SyncState.empty() => SyncState(
    serverTime: DateTime.now(),
    dirty: false,
    orders: const {},
    customers: const {},
    shipments: const {},
    orphans: const {},
  );

  factory SyncState.fromJson(Map<String, dynamic> json) => SyncState(
    serverTime: DateTime.tryParse(json['server_time'] ?? '') ?? DateTime.now(),
    dirty: json['dirty'] == true,
    orders: Map<String, dynamic>.from(json['orders'] ?? {}),
    customers: Map<String, dynamic>.from(json['customers'] ?? {}),
    shipments: Map<String, dynamic>.from(json['shipments'] ?? {}),
    orphans: Map<String, dynamic>.from(json['orphans'] ?? {}),
  );
}

/// Silent Polling Provider
///
/// Polls /api/v1/sync every 12 seconds.
/// Updates only when data has changed (dirty flag).
/// Does NOT show blocking spinners or reset scroll position.
final syncProvider = StateNotifierProvider<SyncNotifier, SyncState>((ref) {
  return SyncNotifier(ref);
});

class SyncNotifier extends StateNotifier<SyncState> {
  final Ref _ref;
  Timer? _timer;
  DateTime? _lastSync;

  SyncNotifier(this._ref) : super(SyncState.empty()) {
    _startPolling();
  }

  Dio get _dio => _ref.read(dioProvider);

  void _startPolling() {
    // Initial fetch
    _poll();
    // Poll every 12 seconds
    _timer = Timer.periodic(const Duration(seconds: 12), (_) => _poll());
  }

  Future<void> _poll() async {
    // Skip if not authenticated
    final token = _ref.read(authTokenProvider);
    if (token == null) return;

    try {
      final params = <String, dynamic>{};
      if (_lastSync != null) {
        params['since'] = _lastSync!.toUtc().toIso8601String();
      }

      final response = await _dio.get('/sync', queryParameters: params);
      final data = response.data as Map<String, dynamic>;
      final newState = SyncState.fromJson(data);

      _lastSync = newState.serverTime;

      // Only update state if there are actual changes
      // This prevents unnecessary widget rebuilds
      if (newState.dirty || state.orders != newState.orders) {
        state = newState;
      }
    } on DioException {
      // Silent fail — polling should never crash the UI
      // Network errors are expected (offline, slow connection)
    }
  }

  /// Force refresh on demand (e.g., after creating an order)
  Future<void> forceSync() => _poll();

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
