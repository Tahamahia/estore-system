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

  Future<Map<String, dynamic>> fetchOrderById(String id) async {
    final response = await _dio.get('/orders/$id');
    return response.data as Map<String, dynamic>;
  }

  Future<void> addItemToOrder(String orderId, Map<String, dynamic> itemData) async {
    await _dio.post('/orders/$orderId/items', data: itemData);
  }

  /// Bulk update item status/shipment for night purchasing workflow
  Future<Map<String, dynamic>> bulkUpdateItems(List<String> itemIds, {String? status, String? shipmentId}) async {
    final response = await _dio.patch('/orders/items/bulk', data: {
      'item_ids': itemIds,
      if (status != null) 'status': status,
      if (shipmentId != null) 'shipment_id': shipmentId,
    });
    return response.data as Map<String, dynamic>;
  }

  /// Fetch unsorted items for Visual Match feature
  Future<List<Map<String, dynamic>>> fetchUnsortedItems() async {
    final response = await _dio.get('/orders/items/unsorted');
    final data = response.data as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['data'] ?? []);
  }

  /// Fetch dispatch readiness by customer (traffic lights)
  Future<List<Map<String, dynamic>>> fetchDispatchStatus() async {
    final response = await _dio.get('/orders/items/dispatch-status');
    final data = response.data as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['data'] ?? []);
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

  /// Search for an existing customer by name. Returns the first matching ID or null.
  Future<String?> searchCustomers(String name) async {
    try {
      final response = await _dio.get('/customers', queryParameters: {'search': name, 'limit': 5});
      final data = response.data as Map<String, dynamic>;
      final customers = List<Map<String, dynamic>>.from(data['data'] ?? []);
      final match = customers.where(
        (c) => (c['full_name'] as String?)?.toLowerCase() == name.toLowerCase(),
      );
      if (match.isNotEmpty) return match.first['id'] as String;
    } catch (_) {}
    return null;
  }

  /// Phone-first identity lookup. Returns customer data if found, null if new.
  Future<Map<String, dynamic>?> lookupByPhone(String phone) async {
    try {
      final cleaned = phone.replaceAll(RegExp(r'[\s\-\(\)\.]'), '');
      if (cleaned.length < 5) return null;
      final response = await _dio.get('/customers', queryParameters: {'phone': cleaned, 'limit': 1});
      final data = response.data as Map<String, dynamic>;
      final customers = List<Map<String, dynamic>>.from(data['data'] ?? []);
      return customers.isNotEmpty ? customers.first : null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> updateCustomer(String id, Map<String, dynamic> data) async {
    final response = await _dio.patch('/customers/$id', data: data);
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

  Future<Map<String, dynamic>> createShipment(Map<String, dynamic> shipmentData) async {
    final response = await _dio.post('/shipments', data: shipmentData);
    await fetchShipments();
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createMasterShipment(Map<String, dynamic> masterData) async {
    final response = await _dio.post('/shipments/master', data: masterData);
    await fetchShipments();
    return response.data as Map<String, dynamic>;
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
