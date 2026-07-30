import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'api_client.dart';

/// Thrown by [CustomersNotifier.lookupByPhone] when a network/server error
/// occurs, distinguishing a real failure from "customer not found" (null return).
class PhoneLookupException implements Exception {
  final String message;
  const PhoneLookupException(this.message);
  @override
  String toString() => message;
}

// ─── Orders Provider ───────────────────────────────────────
final ordersProvider = StateNotifierProvider<OrdersNotifier, AsyncValue<List<Map<String, dynamic>>>>((ref) {
  return OrdersNotifier(ref);
});

class OrdersNotifier extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  final Ref _ref;
  OrdersNotifier(this._ref) : super(const AsyncValue.loading());

  Dio get _dio => _ref.read(dioProvider);

  Future<void> fetchOrders({int page = 1, int limit = 50, String? status, String? search}) async {
    state = const AsyncValue.loading();
    try {
      final queryParams = <String, dynamic>{'page': page, 'limit': limit};
      if (status != null) queryParams['status'] = status;
      if (search != null && search.isNotEmpty) queryParams['search'] = search;

      final response = await _dio.get('/orders', queryParameters: queryParams);
      final data = response.data as Map<String, dynamic>;
      final orders = List<Map<String, dynamic>>.from(data['data'] ?? []);
      state = AsyncValue.data(orders);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Creates an order. Uses the client-generated [orderData]['id'] as the
  /// Idempotency-Key so retries after a timeout don't create duplicates.
  Future<Map<String, dynamic>> createOrder(Map<String, dynamic> orderData) async {
    // Derive a stable key from the client-generated order UUID.
    final key = (orderData['id'] as String?) ?? const Uuid().v4();
    final response = await _dio.post(
      '/orders',
      data: orderData,
      options: Options(headers: {'Idempotency-Key': key}),
    );
    await fetchOrders();
    return response.data as Map<String, dynamic>;
  }

  /// Patches an order. Does NOT refresh the list automatically — callers
  /// (e.g. OrderDetailScreen._loadOrder) are responsible for re-fetching
  /// their own view so the orders list doesn't reload while the detail screen
  /// is still open (race condition / stale-render).
  Future<void> updateOrder(String id, Map<String, dynamic> updates) async {
    await _dio.patch('/orders/$id', data: updates);
  }

  Future<Map<String, dynamic>> fetchOrderById(String id) async {
    final response = await _dio.get('/orders/$id');
    return response.data as Map<String, dynamic>;
  }

  Future<void> addItemToOrder(String orderId, Map<String, dynamic> itemData) async {
    await _dio.post('/orders/$orderId/items', data: itemData);
  }

  /// Update a single order item's fields (name, url, price, qty, size, color, status).
  /// Uses OCC — pass the current item version in [data].
  Future<void> updateOrderItem(String orderId, String itemId, Map<String, dynamic> data) async {
    await _dio.patch('/orders/$orderId/items/$itemId', data: data);
  }

  Future<void> orphanOrderItems(String orderId) async {
    await _dio.post('/orders/$orderId/orphan-items');
  }

  /// Fetches items from a Shein shared-cart link via the backend reverse-engineer proxy.
  /// Returns a list of item maps with keys: name, url, sku, price, qty, size, color.
  Future<List<Map<String, dynamic>>> parseSheinCart(String url) async {
    final response = await _dio.post('/tools/parse-shein-cart', data: {'url': url});
    final data = response.data as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['items'] ?? []);
  }

  /// Bulk update item status/shipment for night purchasing workflow.
  /// Pass [itemIds] when you have resolved item primary keys, or [orderIds]
  /// when you only have order IDs (the backend resolves items server-side).
  Future<Map<String, dynamic>> bulkUpdateItems(
    List<String> itemIds, {
    List<String>? orderIds,
    String? status,
    String? shipmentId,
  }) async {
    final body = <String, dynamic>{};
    if (itemIds.isNotEmpty) body['item_ids'] = itemIds;
    if (orderIds != null && orderIds.isNotEmpty) body['order_ids'] = orderIds;
    if (status != null) body['status'] = status;
    if (shipmentId != null) body['shipment_id'] = shipmentId;
    final response = await _dio.patch('/orders/items/bulk', data: body);
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
  /// Logs errors via debugPrint so callers can still get null on failure without crashing,
  /// but the failure is visible in debug output rather than silently swallowed.
  Future<String?> searchCustomers(String name) async {
    try {
      final response = await _dio.get('/customers', queryParameters: {'search': name, 'limit': 5});
      final data = response.data as Map<String, dynamic>;
      final customers = List<Map<String, dynamic>>.from(data['data'] ?? []);
      final match = customers.where(
        (c) => (c['full_name'] as String?)?.toLowerCase() == name.toLowerCase(),
      );
      if (match.isNotEmpty) return match.first['id'] as String;
    } on DioException catch (e) {
      // ignore: avoid_print
      print('[searchCustomers] Network error for "$name": ${e.message}');
    } catch (e) {
      // ignore: avoid_print
      print('[searchCustomers] Unexpected error for "$name": $e');
    }
    return null;
  }

  /// Phone-first identity lookup.
  /// Returns customer data map if found, or null if no customer has this phone.
  /// Throws [PhoneLookupException] on network/server errors so callers can
  /// distinguish "not found" from "lookup failed" and avoid creating duplicates.
  Future<Map<String, dynamic>?> lookupByPhone(String phone) async {
    final cleaned = phone.replaceAll(RegExp(r'[\s\-\(\)\.]'), '');
    if (cleaned.length < 5) return null;
    try {
      final response = await _dio.get('/customers', queryParameters: {'phone': cleaned, 'limit': 1});
      final data = response.data as Map<String, dynamic>;
      final customers = List<Map<String, dynamic>>.from(data['data'] ?? []);
      return customers.isNotEmpty ? customers.first : null;
    } on DioException catch (e) {
      throw PhoneLookupException('فشل البحث عن العميل (خطأ في الشبكة): ${e.message}');
    } catch (e) {
      throw PhoneLookupException('فشل البحث عن العميل: $e');
    }
  }

  Future<Map<String, dynamic>> updateCustomer(String id, Map<String, dynamic> data) async {
    final response = await _dio.patch('/customers/$id', data: data);
    await fetchCustomers();
    return response.data as Map<String, dynamic>;
  }
}

// ─── External Shipments Provider ──────────────────────────
final externalShipmentsProvider = StateNotifierProvider<ExternalShipmentsNotifier, AsyncValue<List<Map<String, dynamic>>>>((ref) {
  return ExternalShipmentsNotifier(ref);
});

class ExternalShipmentsNotifier extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  final Ref _ref;
  ExternalShipmentsNotifier(this._ref) : super(const AsyncValue.loading());

  Dio get _dio => _ref.read(dioProvider);

  Future<void> fetchShipments({int page = 1}) async {
    state = const AsyncValue.loading();
    try {
      final response = await _dio.get('/external-shipments', queryParameters: {'page': page, 'limit': 50});
      final data = response.data as Map<String, dynamic>;
      state = AsyncValue.data(List<Map<String, dynamic>>.from(data['data'] ?? []));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> createShipment(Map<String, dynamic> shipmentData) async {
    await _dio.post('/external-shipments', data: shipmentData);
    await fetchShipments();
  }

  Future<Map<String, dynamic>> getShipment(String id) async {
    final response = await _dio.get('/external-shipments/$id');
    return response.data as Map<String, dynamic>;
  }

  Future<void> updateShipment(String id, Map<String, dynamic> data) async {
    await _dio.patch('/external-shipments/$id', data: data);
  }

  Future<Map<String, dynamic>> syncTracking(String id) async {
    final response = await _dio.post('/external-shipments/$id/sync');
    return response.data as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> fetchAvailableOrders() async {
    final response = await _dio.get('/external-shipments/available-orders');
    final data = response.data as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['data'] ?? []);
  }

  Future<void> attachOrders(String shipmentId, List<String> orderIds) async {
    await _dio.post('/external-shipments/$shipmentId/attach', data: {'order_ids': orderIds});
  }

  Future<void> deleteShipment(String id) async {
    await _dio.delete('/external-shipments/$id');
    await fetchShipments();
  }
}

// ─── Internal Shipments Provider ──────────────────────────
final internalShipmentsProvider = StateNotifierProvider<InternalShipmentsNotifier, AsyncValue<List<Map<String, dynamic>>>>((ref) {
  return InternalShipmentsNotifier(ref);
});

class InternalShipmentsNotifier extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  final Ref _ref;
  InternalShipmentsNotifier(this._ref) : super(const AsyncValue.loading());

  Dio get _dio => _ref.read(dioProvider);

  Future<void> fetchShipments({int page = 1}) async {
    state = const AsyncValue.loading();
    try {
      final response = await _dio.get('/internal-shipments', queryParameters: {'page': page, 'limit': 50});
      final data = response.data as Map<String, dynamic>;
      state = AsyncValue.data(List<Map<String, dynamic>>.from(data['data'] ?? []));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> createShipment(Map<String, dynamic> shipmentData) async {
    await _dio.post('/internal-shipments', data: shipmentData);
    await fetchShipments();
  }

  Future<Map<String, dynamic>> getShipment(String id) async {
    final response = await _dio.get('/internal-shipments/$id');
    return response.data as Map<String, dynamic>;
  }

  Future<void> updateShipment(String id, Map<String, dynamic> data) async {
    await _dio.patch('/internal-shipments/$id', data: data);
    await fetchShipments();
  }

  Future<List<Map<String, dynamic>>> fetchAvailableOrders() async {
    final response = await _dio.get('/internal-shipments/available-orders');
    final data = response.data as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['data'] ?? []);
  }

  Future<void> attachOrders(String shipmentId, List<String> orderIds) async {
    await _dio.post('/internal-shipments/$shipmentId/attach', data: {'order_ids': orderIds});
    await fetchShipments();
  }

  Future<void> deleteShipment(String id) async {
    await _dio.delete('/internal-shipments/$id');
    await fetchShipments();
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
    } on DioException catch (e) {
      // 4xx responses from warehouse/scan carry useful JSON (e.g. invalid item
      // status). Treat them as data so the scanner UI can show the reason
      // instead of getting stuck on "Processing..." forever.
      final body = e.response?.data;
      if (body is Map<String, dynamic>) {
        state = AsyncValue.data(body);
      } else {
        state = AsyncValue.error(e, StackTrace.current);
      }
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

// ─── Shipping Sources Provider ────────────────────────────
final shippingSourcesProvider = StateNotifierProvider<ShippingSourcesNotifier, AsyncValue<List<Map<String, dynamic>>>>((ref) {
  return ShippingSourcesNotifier(ref);
});

class ShippingSourcesNotifier extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  final Ref _ref;
  ShippingSourcesNotifier(this._ref) : super(const AsyncValue.loading());

  Dio get _dio => _ref.read(dioProvider);

  Future<void> fetchSources() async {
    state = const AsyncValue.loading();
    try {
      final response = await _dio.get('/settings/sources');
      final data = response.data as Map<String, dynamic>;
      state = AsyncValue.data(List<Map<String, dynamic>>.from(data['data'] ?? []));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> createSource(String name, double ratePerKg) async {
    await _dio.post('/settings/sources', data: {'name': name, 'rate_per_kg': ratePerKg});
    await fetchSources();
  }

  Future<void> updateSource(int id, String name, double ratePerKg) async {
    await _dio.put('/settings/sources/$id', data: {'name': name, 'rate_per_kg': ratePerKg});
    await fetchSources();
  }

  Future<void> deleteSource(int id) async {
    await _dio.delete('/settings/sources/$id');
    await fetchSources();
  }
}

// ─── Settlements Provider ──────────────────────────────────
final settlementsProvider = StateNotifierProvider<SettlementsNotifier, AsyncValue<List<Map<String, dynamic>>>>((ref) {
  return SettlementsNotifier(ref);
});

class SettlementsNotifier extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  final Ref _ref;
  SettlementsNotifier(this._ref) : super(const AsyncValue.loading());

  Dio get _dio => _ref.read(dioProvider);

  Future<void> fetchSettlements() async {
    state = const AsyncValue.loading();
    try {
      final response = await _dio.get('/settlements');
      final data = response.data as Map<String, dynamic>;
      state = AsyncValue.data(List<Map<String, dynamic>>.from(data['data'] ?? []));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> createSettlement({
    required String name,
    required double exchangeRate,
    required List<String> orderIds,
  }) async {
    await _dio.post('/settlements', data: {
      'name': name,
      'exchange_rate': exchangeRate,
      'order_ids': orderIds,
    });
    await fetchSettlements();
  }
}

// ─── In-Stock Inventory Provider ──────────────────────────
final inStockProvider = StateNotifierProvider<InStockNotifier, AsyncValue<List<Map<String, dynamic>>>>((ref) {
  return InStockNotifier(ref);
});

class InStockNotifier extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  final Ref _ref;
  InStockNotifier(this._ref) : super(const AsyncValue.loading());

  Dio get _dio => _ref.read(dioProvider);

  Future<void> fetchInStockItems() async {
    state = const AsyncValue.loading();
    try {
      final response = await _dio.get('/inventory/in-stock');
      final data = response.data as Map<String, dynamic>;
      state = AsyncValue.data(List<Map<String, dynamic>>.from(data['data'] ?? []));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> reassignItem(String itemId, String orderId, double newSellingPrice) async {
    await _dio.patch('/inventory/in-stock/$itemId/reassign', data: {
      'order_id': orderId,
      'new_selling_price': newSellingPrice,
    });
    await fetchInStockItems();
  }

  Future<List<Map<String, dynamic>>> fetchActiveOrders() async {
    final response = await _dio.get('/orders', queryParameters: {'limit': 100, 'page': 1});
    final data = response.data as Map<String, dynamic>;
    final orders = List<Map<String, dynamic>>.from(data['data'] ?? []);
    const terminal = ['cancelled', 'auto_cancelled', 'refunded', 'delivered'];
    return orders.where((o) => !terminal.contains(o['status'] as String? ?? '')).toList();
  }
}
