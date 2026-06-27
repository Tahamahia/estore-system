import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_client.dart';

// ─── Orders Provider ───────────────────────────────────────
final ordersProvider = StateNotifierProvider<OrdersNotifier, AsyncValue<List<Map<String, dynamic>>>>((ref) {
  return OrdersNotifier(ref);
});

class OrdersNotifier extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  final Ref _ref;
  OrdersNotifier(this._ref) : super(const AsyncValue.loading());

  Dio get _dio => _ref.read(dioProvider);

  Future<void> fetchOrders({int page = 1, int limit = 50, String? status}) async {
    state = const AsyncValue.loading();
    try {
      final queryParams = <String, dynamic>{'page': page, 'limit': limit};
      if (status != null) queryParams['status'] = status;

      final response = await _dio.get('/orders', queryParameters: queryParams);
      final data = response.data as Map<String, dynamic>;
      final orders = List<Map<String, dynamic>>.from(data['data'] ?? []);
      state = AsyncValue.data(orders);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<Map<String, dynamic>> createOrder(Map<String, dynamic> orderData) async {
    final response = await _dio.post('/orders', data: orderData);
    await fetchOrders();  // Refresh list
    return response.data as Map<String, dynamic>;
  }

  Future<void> updateOrder(String id, Map<String, dynamic> updates) async {
    await _dio.patch('/orders/$id', data: updates);
    await fetchOrders();
  }
}

// ─── Customers Provider ────────────────────────────────────
final customersProvider = StateNotifierProvider<CustomersNotifier, AsyncValue<List<Map<String, dynamic>>>>((ref) {
  return CustomersNotifier(ref);
});

class CustomersNotifier extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  final Ref _ref;
  CustomersNotifier(this._ref) : super(const AsyncValue.loading());

  Dio get _dio => _ref.read(dioProvider);

  Future<void> fetchCustomers({int page = 1}) async {
    state = const AsyncValue.loading();
    try {
      final response = await _dio.get('/customers', queryParameters: {'page': page, 'limit': 50});
      final data = response.data as Map<String, dynamic>;
      state = AsyncValue.data(List<Map<String, dynamic>>.from(data['data'] ?? []));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<Map<String, dynamic>> createCustomer(Map<String, dynamic> data) async {
    final response = await _dio.post('/customers', data: data);
    await fetchCustomers();
    return response.data as Map<String, dynamic>;
  }
}

// ─── Shipments Provider ────────────────────────────────────
final shipmentsProvider = StateNotifierProvider<ShipmentsNotifier, AsyncValue<List<Map<String, dynamic>>>>((ref) {
  return ShipmentsNotifier(ref);
});

class ShipmentsNotifier extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  final Ref _ref;
  ShipmentsNotifier(this._ref) : super(const AsyncValue.loading());

  Dio get _dio => _ref.read(dioProvider);

  Future<void> fetchShipments({int page = 1}) async {
    state = const AsyncValue.loading();
    try {
      final response = await _dio.get('/shipments', queryParameters: {'page': page, 'limit': 50});
      final data = response.data as Map<String, dynamic>;
      state = AsyncValue.data(List<Map<String, dynamic>>.from(data['data'] ?? []));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

// ─── Warehouse Scanner Provider ────────────────────────────
final scanResultProvider = StateNotifierProvider<ScanNotifier, AsyncValue<Map<String, dynamic>?>>((ref) {
  return ScanNotifier(ref);
});

class ScanNotifier extends StateNotifier<AsyncValue<Map<String, dynamic>?>> {
  final Ref _ref;
  ScanNotifier(this._ref) : super(const AsyncValue.data(null));

  Dio get _dio => _ref.read(dioProvider);

  Future<void> scanBarcode(String barcode) async {
    state = const AsyncValue.loading();
    try {
      final response = await _dio.post('/warehouse/scan', data: {'barcode': barcode});
      state = AsyncValue.data(response.data as Map<String, dynamic>);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> logOrphan(Map<String, dynamic> data) async {
    await _dio.post('/warehouse/orphan', data: data);
  }

  void clear() {
    state = const AsyncValue.data(null);
  }
}

// ─── Analytics Provider ────────────────────────────────────
final dashboardProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final dio = ref.read(dioProvider);
  final response = await dio.get('/analytics/dashboard');
  return response.data as Map<String, dynamic>;
});
