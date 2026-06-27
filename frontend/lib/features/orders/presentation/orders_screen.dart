import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:estore_app/app/theme.dart';
import 'package:estore_app/core/providers.dart';
import 'package:uuid/uuid.dart';

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  String _activeFilter = 'all';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(ordersProvider.notifier).fetchOrders());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _applyFilter(String filter) {
    setState(() => _activeFilter = filter);
    ref.read(ordersProvider.notifier).fetchOrders(
      status: filter == 'all' ? null : filter,
    );
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
            for (final f in ['all', 'pending_payment', 'purchased', 'shipped', 'delivered'])
              _FilterChip(
                label: f == 'all' ? 'All' : f.replaceAll('_', ' ').toUpperCase(),
                selected: _activeFilter == f,
                onTap: () => _applyFilter(f),
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
                data: (orders) => orders.isEmpty
                    ? const Center(child: Text('No orders found', style: TextStyle(color: Colors.white38)))
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: orders.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.darkBorder),
                        itemBuilder: (context, index) => _OrderTile(order: orders[index]),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
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
  const _OrderTile({required this.order});

  @override
  Widget build(BuildContext context) {
    final status = (order['status'] ?? 'pending') as String;
    final color = _statusColor(status);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
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
            Text(order['id'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('${order['platform'] ?? 'Manual'} • ${order['currency'] ?? 'USD'}',
              style: const TextStyle(color: Colors.white54, fontSize: 13)),
          ],
        )),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (order['total_local'] != null)
            Text('\$${(order['total_local'] as num).toStringAsFixed(2)}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
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
      ]),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pending_payment': return AppTheme.warning;
      case 'paid': case 'purchasing': return AppTheme.primary;
      case 'purchased': case 'shipped': return AppTheme.secondary;
      case 'delivered': return AppTheme.success;
      case 'cancelled': case 'auto_cancelled': return AppTheme.error;
      default: return AppTheme.accent;
    }
  }
}

// ─── New Order Dialog ──────────────────────────────────────
class _NewOrderDialog extends ConsumerStatefulWidget {
  final VoidCallback onCreated;
  const _NewOrderDialog({required this.onCreated});

  @override
  ConsumerState<_NewOrderDialog> createState() => _NewOrderDialogState();
}

class _NewOrderDialogState extends ConsumerState<_NewOrderDialog> {
  final _customerIdController = TextEditingController();
  final _platformController = TextEditingController(text: 'manual');
  final _rateController = TextEditingController();
  final _productNameController = TextEditingController();
  final _priceController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _customerIdController.dispose();
    _platformController.dispose();
    _rateController.dispose();
    _productNameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _createOrder() async {
    if (_customerIdController.text.isEmpty || _productNameController.text.isEmpty) {
      setState(() => _error = 'Customer ID and product name are required');
      return;
    }

    setState(() { _isLoading = true; _error = null; });

    try {
      final orderId = const Uuid().v4();
      final itemId = const Uuid().v4();

      await ref.read(ordersProvider.notifier).createOrder({
        'id': orderId,
        'customer_id': _customerIdController.text,
        'platform': _platformController.text,
        'pegged_exchange_rate': double.tryParse(_rateController.text),
        'items': [{
          'id': itemId,
          'product_name': _productNameController.text,
          'unit_price_foreign': double.tryParse(_priceController.text) ?? 0,
          'quantity': 1,
        }],
      });

      widget.onCreated();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Create New Order', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white)),
            const SizedBox(height: 24),
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppTheme.error.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_error!, style: const TextStyle(color: AppTheme.error, fontSize: 13)),
              ),
            TextField(
              controller: _customerIdController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Customer ID', prefixIcon: Icon(Icons.person)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _productNameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Product Name', prefixIcon: Icon(Icons.shopping_bag)),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(
                controller: _priceController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Price (Foreign)'),
              )),
              const SizedBox(width: 12),
              Expanded(child: TextField(
                controller: _rateController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Exchange Rate'),
              )),
            ]),
            const SizedBox(height: 24),
            SizedBox(height: 48, child: ElevatedButton(
              onPressed: _isLoading ? null : _createOrder,
              child: _isLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Create Order'),
            )),
          ]),
        ),
      ),
    );
  }
}
