import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:estore_app/app/theme.dart';
import 'package:estore_app/core/api_client.dart';
import 'package:estore_app/core/providers.dart';
import 'package:estore_app/core/utils/dialog_utils.dart';
import 'package:uuid/uuid.dart';

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  String _activeFilter = 'all';
  final _searchController = TextEditingController();
  String _searchText = '';
  Timer? _searchDebounce;
  bool _bulkMode = false;
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(ordersProvider.notifier).fetchOrders());
    _searchController.addListener(() {
      final text = _searchController.text.trim();
      setState(() => _searchText = text.toLowerCase());
      // Debounce server-side search so item-level results (product_name, sku)
      // are fetched after the user stops typing.
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 450), () {
        ref.read(ordersProvider.notifier).fetchOrders(
          status: (_activeFilter == 'all' || _activeFilter == 'settleable')
              ? (_activeFilter == 'settleable' ? 'delivered' : null)
              : _activeFilter,
          search: text.isEmpty ? null : text,
          unsettled: _activeFilter == 'settleable',
        );
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _applyFilter(String filter) {
    setState(() => _activeFilter = filter);
    ref.read(ordersProvider.notifier).fetchOrders(
      status: (filter == 'all' || filter == 'settleable') ? (filter == 'settleable' ? 'delivered' : null) : filter,
      search: _searchText.isEmpty ? null : _searchText,
      unsettled: filter == 'settleable',
    );
  }

  String _filterLabel(String f) {
    switch (f) {
      case 'all': return 'الكل';
      case 'pending': return 'معلق';
      case 'purchased': return 'تم الشراء';
      case 'shipped': return 'شُحن';
      case 'arrived_warehouse': return 'وصل المستودع';
      case 'sorted': return 'مفروز';
      case 'ready_dispatch': return 'جاهز للتوصيل';
      case 'dispatched': return 'خرج للتوصيل';
      case 'delivered': return 'تم التوصيل';
      default: return f.replaceAll('_', ' ');
    }
  }

  void _showNewOrderDialog() {
    showDialog(context: context, builder: (ctx) => _NewOrderDialog(
      onCreated: () => ref.read(ordersProvider.notifier).fetchOrders(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final ordersState = ref.watch(ordersProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('All Orders', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white)),
            const Spacer(),
            // Bulk mode toggle
            TextButton.icon(
              onPressed: () => setState(() { _bulkMode = !_bulkMode; _selectedIds.clear(); }),
              icon: Icon(_bulkMode ? Icons.close : Icons.checklist_rounded, size: 18),
              label: Text(_bulkMode ? 'Cancel' : 'Bulk Select'),
              style: TextButton.styleFrom(foregroundColor: _bulkMode ? AppTheme.error : Colors.white70),
            ),
            if (_bulkMode && _selectedIds.isNotEmpty) ...[
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => _showBulkUpdateDialog(),
                icon: const Icon(Icons.update, size: 18),
                label: Text('Update ${_selectedIds.length} Items'),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.secondary),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => _showCreateSettlementDialog(),
                icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
                label: Text('تسوية (${_selectedIds.length})'),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
              ),
            ],
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _showNewOrderDialog,
              icon: const Icon(Icons.add, size: 20),
              label: const Text('New Order'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
            ),
          ]),
          const SizedBox(height: 20),

          // Filter chips
          Wrap(spacing: 12, runSpacing: 12, children: [
            for (final f in ['all', 'pending', 'purchased', 'shipped', 'arrived_warehouse', 'sorted', 'ready_dispatch', 'dispatched', 'delivered'])
              _FilterChip(
                label: _filterLabel(f),
                selected: _activeFilter == f,
                onTap: () => _applyFilter(f),
              ),
            _FilterChip(
              label: 'جاهزة للتسوية',
              selected: _activeFilter == 'settleable',
              onTap: () => _applyFilter('settleable'),
            ),
          ]),
          const SizedBox(height: 20),

          // Search
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search orders by ID, customer, or product...',
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: const Icon(Icons.search, color: Colors.white38),
              filled: true, fillColor: AppTheme.darkCard,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 20),

          // Orders List
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.darkSurface, borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.darkBorder),
              ),
              child: ordersState.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: AppTheme.error, size: 48),
                    const SizedBox(height: 12),
                    Text('Failed to load orders', style: TextStyle(color: Colors.white70)),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () => ref.read(ordersProvider.notifier).fetchOrders(),
                      child: const Text('Retry'),
                    ),
                  ],
                )),
                data: (orders) {
                  // Apply local search filter
                  final filtered = _searchText.isEmpty ? orders : orders.where((order) {
                    final id = (order['id'] as String? ?? '').toLowerCase();
                    final customer = (order['customer_name'] as String? ?? '').toLowerCase();
                    final notes = (order['notes'] as String? ?? '').toLowerCase();
                    final platform = (order['platform'] as String? ?? '').toLowerCase();
                    return id.contains(_searchText) ||
                        customer.contains(_searchText) ||
                        notes.contains(_searchText) ||
                        platform.contains(_searchText);
                  }).toList();

                  if (filtered.isEmpty) {
                    return const Center(child: Text('No orders found', style: TextStyle(color: Colors.white38)));
                  }
                  return RefreshIndicator(
                    color: AppTheme.primary,
                    onRefresh: () => ref.read(ordersProvider.notifier).fetchOrders(
                      status: (_activeFilter == 'all' || _activeFilter == 'settleable')
                          ? (_activeFilter == 'settleable' ? 'delivered' : null)
                          : _activeFilter,
                      search: _searchText.isEmpty ? null : _searchText,
                      unsettled: _activeFilter == 'settleable',
                    ),
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.darkBorder),
                      itemBuilder: (context, index) {
                        final order = filtered[index];
                        final id = order['id'] as String? ?? '';
                        return _OrderTile(
                          order: order,
                          bulkMode: _bulkMode,
                          selected: _selectedIds.contains(id),
                          onToggle: _bulkMode ? () {
                            setState(() {
                              if (_selectedIds.contains(id)) { _selectedIds.remove(id); }
                              else { _selectedIds.add(id); }
                            });
                          } : null,
                          onTap: !_bulkMode ? () {
                            context.go('/orders/$id');
                          } : null,
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showBulkUpdateDialog() {
    // GET /orders returns order metadata without embedded items.
    // Always send selected order IDs as order_ids so the backend resolves
    // the item list server-side via the order_ids branch of PATCH /orders/items/bulk.
    final orderIds = _selectedIds.toList();

    showDialog(context: context, builder: (_) => _BulkUpdateDialog(
      selectedCount: _selectedIds.length,
      onConfirm: (status) async {
        try {
          await ref.read(ordersProvider.notifier).bulkUpdateItems(
            [], // no pre-resolved item IDs
            orderIds: orderIds,
            status: status,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('✅ ${_selectedIds.length} orders updated to "$status"'),
              backgroundColor: AppTheme.success,
            ));
            setState(() { _bulkMode = false; _selectedIds.clear(); });
            ref.read(ordersProvider.notifier).fetchOrders();
          }
        } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e'), backgroundColor: AppTheme.error));
        }
      },
    ));
  }

  void _showCreateSettlementDialog() {
    final orderIds = _selectedIds.toList();
    showDialog(context: context, builder: (_) => _CreateSettlementDialog(
      selectedCount: orderIds.length,
      onConfirm: (name, rate, writeOff) async {
        try {
          await ref.read(settlementsProvider.notifier).createSettlement(
            name: name,
            exchangeRate: rate,
            orderIds: orderIds,
            writeOff: writeOff,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('✅ تم إنشاء التسوية "$name" لـ ${orderIds.length} طلب'),
              backgroundColor: AppTheme.success,
            ));
            setState(() { _bulkMode = false; _selectedIds.clear(); });
            ref.read(ordersProvider.notifier).fetchOrders();
          }
        } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل إنشاء التسوية: $e'), backgroundColor: AppTheme.error));
        }
      },
    ));
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : AppTheme.darkCard,
          borderRadius: BorderRadius.circular(20),
          border: selected ? null : Border.all(color: AppTheme.darkBorder),
        ),
        child: Text(label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400, fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  final Map<String, dynamic> order;
  final bool bulkMode;
  final bool selected;
  final VoidCallback? onToggle;
  final VoidCallback? onTap;
  const _OrderTile({required this.order, this.bulkMode = false, this.selected = false, this.onToggle, this.onTap});

  String _formatDate(String raw) {
    if (raw.length < 10) return raw.isEmpty ? '—' : raw;
    final parts = raw.substring(0, 10).split('-');
    if (parts.length < 3) return raw.substring(0, 10);
    return '${parts[2]}/${parts[1]}/${parts[0]}';
  }

  @override
  Widget build(BuildContext context) {
    final status = (order['status'] ?? 'pending') as String;
    final color = _statusColor(status);
    final customerName = order['customer_name'] as String? ?? '';
    final rawId = order['id'] as String? ?? '';
    final shortId = '#${rawId.length >= 8 ? rawId.substring(0, 8).toUpperCase() : rawId.toUpperCase()}';

    return InkWell(
      onTap: bulkMode ? onToggle : onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        if (bulkMode) ...[
          Checkbox(
            value: selected,
            onChanged: (_) => onToggle?.call(),
            activeColor: AppTheme.primary,
          ),
        ],
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.receipt_outlined, color: color, size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(shortId,
                style: const TextStyle(color: AppTheme.secondary, fontWeight: FontWeight.w700, fontSize: 11, letterSpacing: 0.5)),
              const SizedBox(width: 8),
              Expanded(child: Text(customerName.isNotEmpty ? customerName : 'عميل غير معروف',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 4),
            Text('${order['platform'] ?? 'Manual'} • ${_formatDate(order['created_at'] as String? ?? '')}',
              style: const TextStyle(color: Colors.white54, fontSize: 13)),
          ],
        )),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (order['settlement_id'] != null)
            Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.success.withValues(alpha: 0.4)),
              ),
              child: const Text('تمت التسوية', style: TextStyle(color: AppTheme.success, fontSize: 10, fontWeight: FontWeight.w600)),
            ),
          Builder(builder: (_) {
            final saleLyd = (order['total_sale_price_lyd'] as num?)?.toDouble()
                ?? (order['items_sale_total_lyd'] as num?)?.toDouble();
            if (saleLyd == null || saleLyd == 0) return const SizedBox.shrink();
            return Text('${saleLyd.toStringAsFixed(0)} د.ل',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600));
          }),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8),
            ),
            child: Text(status.replaceAll('_', ' '),
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ]),
        if (!bulkMode) ...[
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right, color: Colors.white38, size: 20),
        ],
      ]),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pending': return AppTheme.warning;
      case 'purchased':
      case 'shipped': return AppTheme.secondary;
      case 'arrived_warehouse':
      case 'sorted': return AppTheme.accent;
      case 'ready_dispatch':
      case 'dispatched': return const Color(0xFF3B82F6);
      case 'delivered': return AppTheme.success;
      case 'cancelled':
      case 'refunded': return AppTheme.error;
      case 'in_stock':
      case 'transferred_to_inventory': return Colors.orange;
      default: return AppTheme.accent;
    }
  }
}

// ─── New Order Dialog — Manual ERP Entry ──────────────────
class _NewOrderDialog extends ConsumerStatefulWidget {
  final VoidCallback onCreated;
  const _NewOrderDialog({required this.onCreated});
  @override
  ConsumerState<_NewOrderDialog> createState() => _NewOrderDialogState();
}

// Per-item entry for individual_items orders.
// Two generic attribute slots whose labels adapt to the selected category.
class _ItemEntry {
  final TextEditingController nameCtrl;
  final TextEditingController salePriceCtrl;
  final TextEditingController attr1Ctrl; // size / version / shade / details
  final TextEditingController attr2Ctrl; // color / capacity / volume
  String? category; // 'clothing'|'electronics'|'cosmetics'|'general'

  _ItemEntry()
      : nameCtrl = TextEditingController(),
        salePriceCtrl = TextEditingController(),
        attr1Ctrl = TextEditingController(),
        attr2Ctrl = TextEditingController();

  String get attr1Label {
    switch (category) {
      case 'clothing':    return 'المقاس';
      case 'electronics': return 'الإصدار';
      case 'cosmetics':   return 'التظليل';
      default:            return 'تفاصيل';
    }
  }

  String get attr2Label {
    switch (category) {
      case 'clothing':    return 'اللون';
      case 'electronics': return 'السعة';
      case 'cosmetics':   return 'الحجم';
      default:            return '';
    }
  }

  bool get showAttr1 => category != null;
  bool get showAttr2 => category != null && category != 'general';

  Map<String, dynamic> toAttributes() {
    final map = <String, dynamic>{};
    final v1 = attr1Ctrl.text.trim();
    final v2 = attr2Ctrl.text.trim();
    switch (category) {
      case 'clothing':
        if (v1.isNotEmpty) map['size'] = v1;
        if (v2.isNotEmpty) map['color'] = v2;
      case 'electronics':
        if (v1.isNotEmpty) map['version'] = v1;
        if (v2.isNotEmpty) map['capacity'] = v2;
      case 'cosmetics':
        if (v1.isNotEmpty) map['shade'] = v1;
        if (v2.isNotEmpty) map['volume'] = v2;
      case 'general':
        if (v1.isNotEmpty) map['details'] = v1;
    }
    return map;
  }

  void dispose() {
    nameCtrl.dispose();
    salePriceCtrl.dispose();
    attr1Ctrl.dispose();
    attr2Ctrl.dispose();
  }
}

class _NewOrderDialogState extends ConsumerState<_NewOrderDialog> {
  // ── Customer ─────────────────────────────────────────────
  final _phoneCtrl       = TextEditingController();
  final _nameCtrl        = TextEditingController();
  final _phone2Ctrl      = TextEditingController();
  final _cityCtrl        = TextEditingController();
  final _areaCtrl        = TextEditingController();
  final _streetCtrl      = TextEditingController();
  final _locationUrlCtrl = TextEditingController();

  // ── Order ─────────────────────────────────────────────────
  final _cartLinkCtrl       = TextEditingController();
  String _orderType         = 'individual_items';
  final _totalSalePriceCtrl = TextEditingController();
  final List<_ItemEntry> _items = [_ItemEntry()];

  // ── UI state ──────────────────────────────────────────────
  bool _isLoading = false;
  String? _error;

  // Phone-first lookup
  String? _existingCustomerId;
  bool _isLookingUp = false;
  bool _isExisting  = false;
  bool _lookupError = false;
  Timer? _debounce;

  // Category display labels
  static const _categoryOptions = [
    ('clothing',    'ملابس'),
    ('electronics', 'إلكترونيات'),
    ('cosmetics',   'مستحضرات تجميل'),
    ('general',     'عام'),
  ];

  bool get _canSubmit {
    if (_isLoading || _isLookingUp || _lookupError) return false;
    if (_phoneCtrl.text.trim().length < 5) return false;
    if (_nameCtrl.text.trim().isEmpty) return false;
    if (_cartLinkCtrl.text.trim().isEmpty) return false;
    if (_orderType == 'individual_items') {
      final filled = _items.where((i) => i.nameCtrl.text.trim().isNotEmpty).toList();
      if (filled.isEmpty) return false;
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    _phoneCtrl.addListener(_onPhoneChanged);
    _nameCtrl.addListener(() => setState(() {}));
    _cartLinkCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _phoneCtrl.dispose(); _nameCtrl.dispose(); _phone2Ctrl.dispose();
    _cityCtrl.dispose(); _areaCtrl.dispose(); _streetCtrl.dispose();
    _locationUrlCtrl.dispose(); _cartLinkCtrl.dispose(); _totalSalePriceCtrl.dispose();
    for (final item in _items) { item.dispose(); }
    super.dispose();
  }

  void _onPhoneChanged() {
    _debounce?.cancel();
    final phone = _phoneCtrl.text.trim();
    if (phone.length < 5) {
      setState(() { _isExisting = false; _existingCustomerId = null; _lookupError = false; });
      return;
    }
    setState(() { _isLookingUp = true; _lookupError = false; });
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final result = await ref.read(customersProvider.notifier).lookupByPhone(phone);
        if (!mounted) return;
        setState(() {
          _isLookingUp = false; _lookupError = false;
          if (result != null) {
            _isExisting = true;
            _existingCustomerId = result['id'] as String?;
            _nameCtrl.text = result['full_name'] as String? ?? '';
          } else {
            _isExisting = false; _existingCustomerId = null;
          }
        });
      } on PhoneLookupException catch (e) {
        if (!mounted) return;
        setState(() { _isLookingUp = false; _lookupError = true; _isExisting = false; _existingCustomerId = null; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()), backgroundColor: AppTheme.error,
          action: SnackBarAction(label: 'إعادة المحاولة', textColor: Colors.white, onPressed: _onPhoneChanged),
        ));
      }
    });
  }

  void _addItem()       => setState(() => _items.add(_ItemEntry()));
  void _removeItem(int i) {
    if (_items.length <= 1) return;
    setState(() { _items[i].dispose(); _items.removeAt(i); });
  }

  Future<void> _createOrder() async {
    if (_phoneCtrl.text.trim().isEmpty) { setState(() => _error = 'رقم الهاتف مطلوب'); return; }
    if (_nameCtrl.text.trim().isEmpty)  { setState(() => _error = 'اسم العميل مطلوب'); return; }
    if (_cartLinkCtrl.text.trim().isEmpty) { setState(() => _error = 'رابط السلة مطلوب'); return; }
    if (_orderType == 'individual_items') {
      final filled = _items.where((i) => i.nameCtrl.text.trim().isNotEmpty).toList();
      if (filled.isEmpty) { setState(() => _error = 'يجب إدخال اسم منتج واحد على الأقل'); return; }
    }
    setState(() { _isLoading = true; _error = null; });
    try {
      String customerId;
      if (_isExisting && _existingCustomerId != null) {
        customerId = _existingCustomerId!;
      } else {
        final custResult = await ref.read(customersProvider.notifier).createCustomer({
          'id': const Uuid().v4(),
          'full_name': _nameCtrl.text.trim(),
          'phone': _phoneCtrl.text.trim(),
          if (_phone2Ctrl.text.trim().isNotEmpty)      'phone2':       _phone2Ctrl.text.trim(),
          if (_cityCtrl.text.trim().isNotEmpty)        'city':         _cityCtrl.text.trim(),
          if (_areaCtrl.text.trim().isNotEmpty)        'area':         _areaCtrl.text.trim(),
          if (_streetCtrl.text.trim().isNotEmpty)      'street':       _streetCtrl.text.trim(),
          if (_locationUrlCtrl.text.trim().isNotEmpty) 'location_url': _locationUrlCtrl.text.trim(),
        });
        customerId = custResult['id'] as String;
      }

      final orderId = const Uuid().v4();
      final orderItems = _orderType == 'individual_items'
        ? _items.where((i) => i.nameCtrl.text.trim().isNotEmpty).map((i) {
            final attrs = i.toAttributes();
            return {
              'id':            const Uuid().v4(),
              'product_name':  i.nameCtrl.text.trim(),
              'name':          i.nameCtrl.text.trim(),
              'sale_price_lyd': double.tryParse(i.salePriceCtrl.text.trim()),
              'unit_price_local': double.tryParse(i.salePriceCtrl.text.trim()) ?? 0,
              if (i.category != null) 'category':      i.category,
              if (i.category != null) 'item_category': i.category,
              if (attrs.isNotEmpty) 'attributes': jsonEncode(attrs),
            };
          }).toList()
        : <Map<String, dynamic>>[];

      await ref.read(ordersProvider.notifier).createOrder({
        'id':          orderId,
        'customer_id': customerId,
        'cart_link':   _cartLinkCtrl.text.trim(),
        'order_type':  _orderType,
        'platform':    'manual',
        if (_orderType == 'full_cart' && _totalSalePriceCtrl.text.trim().isNotEmpty)
          'total_sale_price_lyd': double.tryParse(_totalSalePriceCtrl.text.trim()),
        'items': orderItems,
      });
      widget.onCreated();
      if (mounted) Navigator.of(context).pop();
    } on DioException catch (e) {
      final data = e.response?.data;
      final errorMsg = data is Map<String, dynamic>
          ? (data['message'] as String?
              ?? data['error'] as String?
              ?? 'حدث خطأ غير معروف')
          : (data?.toString() ?? 'حدث خطأ في الاتصال بالخادم');
      if (mounted) setState(() => _error = errorMsg);
    } catch (e) {
      final raw = e.toString();
      if (mounted) setState(() => _error = raw.startsWith('Exception: ') ? raw.substring(11) : raw);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: isMobile(context) ? 8 : 40, vertical: 24),
      backgroundColor: AppTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: dialogMaxWidth(context, desktopMax: 540), maxHeight: dialogMaxHeight(context, cap: 900)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // ── Header ───────────────────────────────────────────
            Row(children: [
              const Icon(Icons.receipt_long_outlined, color: AppTheme.primary, size: 22),
              const SizedBox(width: 10),
              const Expanded(child: Text('طلب جديد', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white))),
              IconButton(icon: const Icon(Icons.close, color: Colors.white38), onPressed: () => Navigator.of(context).pop(), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
            ]),
            const SizedBox(height: 20),

            if (_error != null) Container(
              padding: const EdgeInsets.all(10), margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(color: AppTheme.error.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
              child: Text(_error!, style: const TextStyle(color: AppTheme.error, fontSize: 13)),
            ),

            Flexible(child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // ── 1. Phone-first ──────────────────────────────────
              const _SectionHeader(icon: Icons.person_outline, label: 'بيانات العميل'),
              const SizedBox(height: 10),
              TextField(
                controller: _phoneCtrl, style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'رقم الهاتف *',
                  prefixIcon: const Icon(Icons.phone),
                  suffixIcon: _isLookingUp
                    ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                    : _lookupError  ? const Icon(Icons.wifi_off, color: AppTheme.error)
                    : _isExisting   ? const Icon(Icons.check_circle, color: AppTheme.success)
                    : _phoneCtrl.text.length >= 5 ? const Icon(Icons.person_add, color: AppTheme.accent)
                    : null,
                ),
              ),
              if (_lookupError) _inlineBanner(AppTheme.error, Icons.wifi_off, 'تعذر البحث — تحقق من الاتصال', action: TextButton(onPressed: _onPhoneChanged, style: TextButton.styleFrom(foregroundColor: AppTheme.error, padding: EdgeInsets.zero, minimumSize: const Size(50, 28)), child: const Text('إعادة', style: TextStyle(fontSize: 12)))),
              if (_isExisting && !_lookupError)     _inlineBanner(AppTheme.success, Icons.check_circle_outline, '✅ عميل موجود'),
              if (!_isExisting && !_lookupError && _phoneCtrl.text.length >= 5 && !_isLookingUp)
                _inlineBanner(AppTheme.accent, Icons.person_add_alt_1, '🆕 عميل جديد'),
              const SizedBox(height: 10),
              TextField(
                controller: _nameCtrl,
                readOnly: _isExisting,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'اسم العميل *', prefixIcon: const Icon(Icons.person),
                  filled: _isExisting, fillColor: _isExisting ? AppTheme.darkCard.withValues(alpha: 0.5) : null,
                ),
              ),
              if (!_isExisting && _phoneCtrl.text.trim().length >= 5 && !_isLookingUp) ...[
                const SizedBox(height: 8),
                LayoutBuilder(builder: (context, constraints) {
                  if (constraints.maxWidth < 400) {
                    return Column(children: [
                      _compactField(_phone2Ctrl, 'رقم ثاني', Icons.phone_outlined),
                      const SizedBox(height: 6),
                      _compactField(_cityCtrl, 'المدينة', Icons.location_city),
                    ]);
                  }
                  return Row(children: [
                    Expanded(child: _compactField(_phone2Ctrl, 'رقم ثاني', Icons.phone_outlined)),
                    const SizedBox(width: 8),
                    Expanded(child: _compactField(_cityCtrl, 'المدينة', Icons.location_city)),
                  ]);
                }),
                const SizedBox(height: 6),
                LayoutBuilder(builder: (context, constraints) {
                  if (constraints.maxWidth < 400) {
                    return Column(children: [
                      _compactField(_areaCtrl, 'المنطقة', Icons.map_outlined),
                      const SizedBox(height: 6),
                      _compactField(_streetCtrl, 'الشارع', Icons.home_outlined),
                    ]);
                  }
                  return Row(children: [
                    Expanded(child: _compactField(_areaCtrl, 'المنطقة', Icons.map_outlined)),
                    const SizedBox(width: 8),
                    Expanded(child: _compactField(_streetCtrl, 'الشارع', Icons.home_outlined)),
                  ]);
                }),
                const SizedBox(height: 6),
                _compactField(_locationUrlCtrl, 'رابط اللوكيشن', Icons.location_on_outlined, type: TextInputType.url),
              ],

              const SizedBox(height: 18),

              // ── 2. Cart link ─────────────────────────────────────
              const _SectionHeader(icon: Icons.link, label: 'رابط السلة'),
              const SizedBox(height: 10),
              TextField(
                controller: _cartLinkCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'رابط السلة المشتركة *',
                  hintText: 'https://shein.top/...',
                  hintStyle: TextStyle(color: Colors.white24),
                  prefixIcon: Icon(Icons.shopping_cart_outlined, size: 18),
                  isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),

              const SizedBox(height: 18),

              // ── 3. Order type ────────────────────────────────────
              const _SectionHeader(icon: Icons.category_outlined, label: 'نوع الطلب'),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _orderTypeChip('full_cart', 'سلة تامة', Icons.shopping_basket)),
                const SizedBox(width: 10),
                Expanded(child: _orderTypeChip('individual_items', 'منتجات متفرقة', Icons.list_alt)),
              ]),

              const SizedBox(height: 16),

              // ── 4a. Full-cart: single total price ────────────────
              if (_orderType == 'full_cart') ...[
                _compactField(_totalSalePriceCtrl, 'إجمالي سعر البيع (د.ل) *', Icons.sell_outlined,
                  type: const TextInputType.numberWithOptions(decimal: true)),
                const SizedBox(height: 4),
                Text('سيُدخل الأدمن تكلفة الشراء لاحقاً', style: TextStyle(color: Colors.white38, fontSize: 11)),
              ],

              // ── 4b. Individual items: dynamic list ───────────────
              if (_orderType == 'individual_items') ...[
                Row(children: [
                  const Text('المنتجات', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _addItem,
                    icon: const Icon(Icons.add_circle_outline, size: 18, color: AppTheme.secondary),
                    label: const Text('إضافة منتج', style: TextStyle(color: AppTheme.secondary, fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ]),
                const SizedBox(height: 6),
                ListView.separated(
                  shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, index) => _ItemCard(
                    entry: _items[index],
                    index: index,
                    canRemove: _items.length > 1,
                    categoryOptions: _categoryOptions,
                    onRemove: () => _removeItem(index),
                    onChanged: () => setState(() {}),
                  ),
                ),
              ],
            ]))),

            const SizedBox(height: 18),
            if (!_canSubmit && _phoneCtrl.text.trim().length >= 5 && !_isLookingUp && _nameCtrl.text.trim().isEmpty)
              _inlineBanner(AppTheme.warning, Icons.info_outline, 'أدخل اسم العميل للمتابعة'),
            SizedBox(height: 50, child: ElevatedButton(
              onPressed: _canSubmit ? _createOrder : null,
              child: _isLoading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : _isLookingUp
                  ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                      SizedBox(width: 8), Text('جاري البحث...'),
                    ])
                  : Text('إنشاء الطلب${_orderType == 'individual_items' ? ' (${_items.length} منتج)' : ''}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            )),
          ]),
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────

  Widget _orderTypeChip(String value, String label, IconData icon) {
    final selected = _orderType == value;
    return GestureDetector(
      onTap: () => setState(() => _orderType = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary.withValues(alpha: 0.2) : AppTheme.darkCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppTheme.primary : AppTheme.darkBorder, width: selected ? 1.5 : 1),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 16, color: selected ? AppTheme.primary : Colors.white54),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: selected ? AppTheme.primary : Colors.white70, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, fontSize: 13)),
        ]),
      ),
    );
  }

  Widget _inlineBanner(Color color, IconData icon, String text, {Widget? action}) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        Icon(icon, color: color, size: 15), const SizedBox(width: 6),
        Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 12))),
        if (action != null) action,
      ]),
    );
  }

  Widget _compactField(TextEditingController ctrl, String label, IconData icon, {TextInputType? type}) {
    return TextField(
      controller: ctrl, style: const TextStyle(color: Colors.white, fontSize: 13),
      keyboardType: type,
      decoration: InputDecoration(
        labelText: label, prefixIcon: Icon(icon, size: 17),
        isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }
}

// ── Reusable section header ───────────────────────────────
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionHeader({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 15, color: AppTheme.primary),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 0.3)),
      const SizedBox(width: 8),
      const Expanded(child: Divider(color: AppTheme.darkBorder, height: 1)),
    ]);
  }
}

// ── Item card for individual_items orders ─────────────────
class _ItemCard extends StatefulWidget {
  final _ItemEntry entry;
  final int index;
  final bool canRemove;
  final List<(String, String)> categoryOptions;
  final VoidCallback onRemove;
  final VoidCallback onChanged;
  const _ItemCard({required this.entry, required this.index, required this.canRemove, required this.categoryOptions, required this.onRemove, required this.onChanged});
  @override
  State<_ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<_ItemCard> {
  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.darkCard.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
            child: Text('${widget.index + 1}', style: const TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
          const Spacer(),
          if (widget.canRemove)
            IconButton(icon: const Icon(Icons.delete_outline, color: AppTheme.error, size: 18), onPressed: widget.onRemove, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
        ]),
        const SizedBox(height: 8),
        // Product name
        TextField(
          controller: entry.nameCtrl, style: const TextStyle(color: Colors.white, fontSize: 13),
          onChanged: (_) => widget.onChanged(),
          decoration: const InputDecoration(labelText: 'اسم المنتج *', prefixIcon: Icon(Icons.shopping_bag, size: 17), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
        ),
        const SizedBox(height: 8),
        // Sale price + category
        Row(children: [
          Expanded(child: TextField(
            controller: entry.salePriceCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: const InputDecoration(labelText: 'سعر البيع (د.ل)', prefixIcon: Icon(Icons.sell_outlined, size: 17), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
          )),
          const SizedBox(width: 8),
          Expanded(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
            decoration: BoxDecoration(color: AppTheme.darkCard, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.darkBorder)),
            child: DropdownButtonHideUnderline(child: DropdownButton<String?>(
              value: entry.category, isExpanded: true, dropdownColor: AppTheme.darkCard,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              icon: const Icon(Icons.expand_more, color: Colors.white54, size: 18),
              hint: const Text('الفئة', style: TextStyle(color: Colors.white38, fontSize: 13)),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('—', style: TextStyle(color: Colors.white38))),
                ...widget.categoryOptions.map((o) => DropdownMenuItem(value: o.$1, child: Text(o.$2, style: const TextStyle(color: Colors.white)))),
              ],
              onChanged: (v) => setState(() { entry.category = v; }),
            )),
          )),
        ]),
        // Dynamic attribute fields
        if (entry.showAttr1) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(
              controller: entry.attr1Ctrl, style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(labelText: entry.attr1Label, isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
            )),
            if (entry.showAttr2) ...[
              const SizedBox(width: 8),
              Expanded(child: TextField(
                controller: entry.attr2Ctrl, style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(labelText: entry.attr2Label, isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
              )),
            ],
          ]),
        ],
      ]),
    );
  }
}

// ─── Create Settlement Dialog ──────────────────────────────
class _CreateSettlementDialog extends ConsumerStatefulWidget {
  final int selectedCount;
  final Future<void> Function(String name, double rate, bool writeOff) onConfirm;
  const _CreateSettlementDialog({required this.selectedCount, required this.onConfirm});
  @override
  ConsumerState<_CreateSettlementDialog> createState() => _CreateSettlementDialogState();
}

class _CreateSettlementDialogState extends ConsumerState<_CreateSettlementDialog> {
  final _nameCtrl = TextEditingController();
  final _rateCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _writeOff = false;
  late Future<int> _inStockCountFuture;

  @override
  void initState() {
    super.initState();
    _inStockCountFuture = _fetchInStockCount();
  }

  Future<int> _fetchInStockCount() async {
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.get('/inventory/in-stock', queryParameters: {'limit': 1, 'page': 1});
      final data = res.data as Map<String, dynamic>;
      return (data['total'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _rateCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: isMobile(context) ? 8 : 40, vertical: 24),
      backgroundColor: AppTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: dialogMaxWidth(context, desktopMax: 420), maxHeight: dialogMaxHeight(context, cap: 600)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppTheme.success.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.account_balance_wallet_outlined, color: AppTheme.success, size: 22),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('إنشاء تسوية مالية', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
                Text('${widget.selectedCount} طلب محدد', style: const TextStyle(color: Colors.white54, fontSize: 13)),
              ]),
            ]),
            const SizedBox(height: 24),
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: AppTheme.error.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                child: Text(_error!, style: const TextStyle(color: AppTheme.error, fontSize: 13)),
              ),
            ],
            TextField(
              controller: _nameCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'اسم الدفعة *',
                hintText: 'مثال: دفعة يوليو 2025',
                hintStyle: TextStyle(color: Colors.white24),
                prefixIcon: Icon(Icons.label_outline),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _rateCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'سعر الصرف الفعلي (د.ل / \$) *',
                hintText: 'مثال: 5.85',
                hintStyle: TextStyle(color: Colors.white24),
                prefixIcon: Icon(Icons.currency_exchange_outlined),
              ),
            ),
            const SizedBox(height: 16),
            // Write-off checkbox
            Container(
              decoration: BoxDecoration(
                color: AppTheme.darkCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _writeOff ? AppTheme.warning.withValues(alpha: 0.4) : AppTheme.darkBorder),
              ),
              child: CheckboxListTile(
                value: _writeOff,
                onChanged: (v) => setState(() => _writeOff = v ?? false),
                activeColor: AppTheme.warning,
                title: const Text(
                  'شطب البضاعة الفورية غير المباعة في هذه التسوية',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                dense: true,
              ),
            ),
            const SizedBox(height: 6),
            FutureBuilder<int>(
              future: _inStockCountFuture,
              builder: (ctx, snap) {
                final count = snap.data ?? 0;
                if (_writeOff) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.warning.withValues(alpha: 0.25)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.warning_amber_rounded, color: AppTheme.warning, size: 15),
                      const SizedBox(width: 6),
                      Text(
                        'سيتم شطب $count منتج كخسارة',
                        style: const TextStyle(color: AppTheme.warning, fontSize: 12),
                      ),
                    ]),
                  );
                }
                return const Text(
                  'لن يتم شطب أي بضاعة فورية',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                );
              },
            ),
            const SizedBox(height: 24),
            SizedBox(height: 48, child: ElevatedButton.icon(
              onPressed: _loading ? null : () async {
                final name = _nameCtrl.text.trim();
                final rate = double.tryParse(_rateCtrl.text.trim());
                if (name.isEmpty) { setState(() => _error = 'اسم الدفعة مطلوب'); return; }
                if (rate == null || rate <= 0) { setState(() => _error = 'سعر الصرف يجب أن يكون رقماً موجباً'); return; }
                setState(() { _loading = true; _error = null; });
                final nav = Navigator.of(context);
                await widget.onConfirm(name, rate, _writeOff);
                if (mounted) nav.pop();
              },
              icon: _loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check, size: 20),
              label: Text(_loading ? 'جاري الإنشاء...' : 'إنشاء التسوية'),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
            )),
          ])),
        ),
      ),
    );
  }
}

// ─── Bulk Update Dialog ────────────────────────────────────
class _BulkUpdateDialog extends StatefulWidget {
  final int selectedCount;
  final Future<void> Function(String status) onConfirm;
  const _BulkUpdateDialog({required this.selectedCount, required this.onConfirm});
  @override
  State<_BulkUpdateDialog> createState() => _BulkUpdateDialogState();
}

class _BulkUpdateDialogState extends State<_BulkUpdateDialog> {
  String _status = 'purchased';
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: isMobile(context) ? 8 : 40, vertical: 24),
      backgroundColor: AppTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: dialogMaxWidth(context, desktopMax: 420)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppTheme.secondary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.checklist_rounded, color: AppTheme.secondary, size: 22),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Bulk Update', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
                Text('${widget.selectedCount} items selected', style: const TextStyle(color: Colors.white54, fontSize: 13)),
              ]),
            ]),
            const SizedBox(height: 24),
            const Text('Set status for all selected:', style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in ['purchased', 'shipped', 'arrived_warehouse', 'sorted', 'ready_dispatch', 'dispatched', 'delivered'])
                ChoiceChip(
                  label: Text(s.replaceAll('_', ' ')),
                  selected: _status == s,
                  onSelected: (_) => setState(() => _status = s),
                  selectedColor: AppTheme.primary,
                  backgroundColor: AppTheme.darkCard,
                  labelStyle: TextStyle(color: _status == s ? Colors.white : Colors.white70, fontSize: 12),
                ),
            ]),
            const SizedBox(height: 24),
            SizedBox(height: 48, child: ElevatedButton.icon(
              onPressed: _loading ? null : () async {
                final nav = Navigator.of(context);
                setState(() => _loading = true);
                await widget.onConfirm(_status);
                if (mounted) nav.pop();
              },
              icon: _loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check, size: 20),
              label: Text(_loading ? 'Updating...' : 'Apply to ${widget.selectedCount} Items'),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
            )),
          ]),
        ),
      ),
    );
  }
}
