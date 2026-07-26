import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'package:estore_app/app/theme.dart';
import 'package:estore_app/core/providers.dart';

/// Order Detail Screen — shows full order info, items, and action buttons.
class OrderDetailScreen extends ConsumerStatefulWidget {
  final String orderId;
  const OrderDetailScreen({super.key, required this.orderId});

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen> {
  Map<String, dynamic>? _order;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOrder();
  }

  Future<void> _loadOrder() async {
    setState(() { _loading = true; _error = null; });
    try {
      // Always fetch directly from the API so items and customer data are included.
      // GET /orders/:id returns the full order with a customer JOIN and nested items array.
      final order = await ref.read(ordersProvider.notifier).fetchOrderById(widget.orderId);
      setState(() { _order = order; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  String _translateStatus(String status) {
    switch (status) {
      case 'pending_payment': return 'في انتظار الدفع';
      case 'paid': return 'تم الدفع';
      case 'purchasing': return 'جاري الشراء';
      case 'purchased': return 'تم الشراء';
      case 'shipped': return 'تم الشحن';
      case 'arrived_warehouse': return 'وصل المخزن';
      case 'sorted': return 'تم الفرز';
      case 'ready_dispatch': return 'جاهز للتوصيل';
      case 'dispatched': return 'في الطريق';
      case 'delivered': return 'تم التوصيل';
      case 'cancelled': return 'ملغي';
      case 'auto_cancelled': return 'ملغي تلقائياً';
      default: return status.replaceAll('_', ' ');
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pending_payment': return AppTheme.warning;
      case 'paid': case 'purchasing': return AppTheme.primary;
      case 'purchased': case 'shipped': return AppTheme.secondary;
      case 'arrived_warehouse': case 'sorted': return AppTheme.accent;
      case 'ready_dispatch': return AppTheme.success;
      case 'dispatched': return const Color(0xFF3B82F6);
      case 'delivered': return AppTheme.success;
      case 'cancelled': case 'auto_cancelled': return AppTheme.error;
      default: return AppTheme.accent;
    }
  }

  void _openWhatsApp(String? phone, String name) async {
    if (phone == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يوجد رقم هاتف'), backgroundColor: AppTheme.warning));
      return;
    }
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final items = _order?['items'] as List<dynamic>? ?? [];
    final orderStatus = _order?['status'] as String? ?? 'pending';
    final msg = Uri.encodeComponent('مرحبا $name، طلبك المكون من ${items.length} عناصر حالته: ${_translateStatus(orderStatus)}.');
    final url = Uri.parse('https://wa.me/$cleanPhone?text=$msg');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  void _callPhone(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final url = Uri.parse('tel:$cleanPhone');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  void _showEditOrderDialog() {
    showDialog(
      context: context,
      builder: (_) => _EditOrderDialog(
        order: _order!,
        onSave: (updates) async {
          await ref.read(ordersProvider.notifier).updateOrder(widget.orderId, updates);
          await _loadOrder();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('✅ تم تحديث الطلب'),
              backgroundColor: AppTheme.success,
            ));
          }
        },
      ),
    );
  }

  void _showItemEditDialog(Map<String, dynamic> item) {
    String selectedStatus = (item['status'] as String?) ?? 'pending';
    showDialog(context: context, builder: (ctx) => Dialog(
      backgroundColor: AppTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: StatefulBuilder(builder: (_, setDialogState) {
            return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(item['product_name'] as String? ?? 'المنتج',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              const Text('تغيير حالة العنصر', style: TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(height: 20),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final s in ['pending', 'purchased', 'shipped', 'arrived_warehouse', 'sorted', 'ready_dispatch', 'dispatched', 'delivered'])
                  ChoiceChip(
                    label: Text(_translateStatus(s)),
                    selected: selectedStatus == s,
                    onSelected: (_) => setDialogState(() => selectedStatus = s),
                    selectedColor: _statusColor(s),
                    backgroundColor: AppTheme.darkCard,
                    labelStyle: TextStyle(color: selectedStatus == s ? Colors.white : Colors.white70, fontSize: 12),
                  ),
              ]),
              const SizedBox(height: 24),
              SizedBox(height: 48, child: ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await ref.read(ordersProvider.notifier).bulkUpdateItems(
                      [item['id'] as String],
                      status: selectedStatus,
                    );
                    await _loadOrder();
                    if (mounted) {
                      messenger.showSnackBar(SnackBar(
                        content: Text('✅ تم تحديث العنصر إلى ${_translateStatus(selectedStatus)}'),
                        backgroundColor: AppTheme.success,
                      ));
                    }
                  } catch (e) {
                    if (mounted) {
                      messenger.showSnackBar(SnackBar(content: Text('فشل: $e'), backgroundColor: AppTheme.error));
                    }
                  }
                },
                icon: const Icon(Icons.check, size: 20),
                label: const Text('تحديث الحالة'),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
              )),
            ]);
          }),
        ),
      ),
    ));
  }

  void _showAddItemDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _AddItemDialog(
        orderId: widget.orderId,
        onAdded: () async {
          await _loadOrder();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('✅ تم إضافة المنتج للطلب'),
              backgroundColor: AppTheme.success,
            ));
          }
        },
      ),
    );
  }

  void _showUpdateStatusDialog() {
    String selectedStatus = (_order?['status'] as String?) ?? 'pending_payment';
    showDialog(context: context, builder: (ctx) => Dialog(
      backgroundColor: AppTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: StatefulBuilder(builder: (context, setDialogState) {
            return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('تحديث الحالة', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
              const SizedBox(height: 8),
              const Text('اختر الحالة الجديدة للطلب', style: TextStyle(color: Colors.white54, fontSize: 14)),
              const SizedBox(height: 20),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final s in ['pending_payment', 'purchased', 'shipped', 'arrived_warehouse', 'sorted', 'ready_dispatch', 'dispatched', 'delivered'])
                  ChoiceChip(
                    label: Text(_translateStatus(s)),
                    selected: selectedStatus == s,
                    onSelected: (_) => setDialogState(() => selectedStatus = s),
                    selectedColor: _statusColor(s),
                    backgroundColor: AppTheme.darkCard,
                    labelStyle: TextStyle(color: selectedStatus == s ? Colors.white : Colors.white70, fontSize: 13),
                  ),
              ]),
              const SizedBox(height: 24),
              SizedBox(height: 52, child: ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  try {
                    await ref.read(ordersProvider.notifier).updateOrder(widget.orderId, {
                      'status': selectedStatus,
                      'version': _order?['version'],
                    });
                    await _loadOrder();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('✅ تم تحديث الحالة إلى ${_translateStatus(selectedStatus)}'),
                        backgroundColor: AppTheme.success,
                      ));
                    }
                  } catch (e) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل: $e'), backgroundColor: AppTheme.error));
                  }
                },
                icon: const Icon(Icons.check, size: 22),
                label: const Text('تحديث', style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
              )),
            ]);
          }),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null || _order == null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline, color: AppTheme.error, size: 56),
        const SizedBox(height: 16),
        Text(_error ?? 'Order not found', style: const TextStyle(color: Colors.white70, fontSize: 16)),
        const SizedBox(height: 16),
        ElevatedButton.icon(onPressed: _loadOrder, icon: const Icon(Icons.refresh), label: const Text('إعادة المحاولة')),
      ]));
    }

    final order = _order!;
    final status = (order['status'] ?? 'pending') as String;
    final customerName = order['customer_name'] as String? ?? 'غير معروف';
    final phone = order['customer_phone'] as String? ?? order['phone'] as String?;
    final platform = order['platform'] as String? ?? 'Manual';
    final createdAt = order['created_at'] as String? ?? '';
    final items = order['items'] as List<dynamic>? ?? [];
    final hasReadyItems = items.any((item) {
      final s = (item as Map<String, dynamic>)['status'] as String? ?? '';
      return s == 'sorted' || s == 'ready_dispatch';
    });

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back button + title + edit button
          Row(children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 28),
              onPressed: () {
                if (context.canPop()) { context.pop(); } else { context.go('/orders'); }
              },
            ),
            const SizedBox(width: 8),
            Expanded(child: Text('تفاصيل الطلب', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white))),
            IconButton(
              icon: const Icon(Icons.edit_outlined, color: Colors.white70, size: 22),
              tooltip: 'تعديل الطلب',
              onPressed: _order != null ? _showEditOrderDialog : null,
            ),
          ]),
          const SizedBox(height: 20),

          // Order header card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.darkSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _statusColor(status).withValues(alpha: 0.4)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppTheme.primary.withValues(alpha: 0.2),
                  child: Text(customerName.isNotEmpty ? customerName[0] : '?',
                    style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700, fontSize: 20)),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(customerName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
                  const SizedBox(height: 4),
                  if (phone != null && phone.isNotEmpty)
                    GestureDetector(
                      onTap: () => _callPhone(phone),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.phone, color: AppTheme.secondary, size: 16),
                        const SizedBox(width: 6),
                        Text(phone, style: const TextStyle(color: AppTheme.secondary, fontSize: 14, fontWeight: FontWeight.w500, decoration: TextDecoration.underline)),
                      ]),
                    ),
                ])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: _statusColor(status).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _statusColor(status).withValues(alpha: 0.4)),
                  ),
                  child: Text(_translateStatus(status),
                    style: TextStyle(color: _statusColor(status), fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                _InfoChip(icon: Icons.storefront, label: platform),
                const SizedBox(width: 12),
                if (createdAt.isNotEmpty) _InfoChip(icon: Icons.calendar_today, label: createdAt.length > 10 ? createdAt.substring(0, 10) : createdAt),
                const SizedBox(width: 12),
                _InfoChip(icon: Icons.shopping_bag, label: '${items.length} عنصر'),
              ]),
            ]),
          ),
          const SizedBox(height: 20),

          // Items list header with "Add Item" button
          Row(children: [
            Text('العناصر (${items.length})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
            const Spacer(),
            TextButton.icon(
              onPressed: _showAddItemDialog,
              icon: const Icon(Icons.add_circle, color: AppTheme.secondary, size: 20),
              label: const Text('إضافة منتج', style: TextStyle(color: AppTheme.secondary, fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 12),

          // Items list
          Expanded(
            child: items.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.shopping_bag_outlined, color: Colors.white24, size: 56),
                  const SizedBox(height: 12),
                  const Text('لا توجد عناصر في هذا الطلب', style: TextStyle(color: Colors.white38, fontSize: 16)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _showAddItemDialog,
                    icon: const Icon(Icons.add_shopping_cart),
                    label: const Text('إضافة أول منتج'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14)),
                  ),
                ]))
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = items[index] as Map<String, dynamic>;
                    return _OrderItemCard(item: item, statusColor: _statusColor, translateStatus: _translateStatus, onEditStatus: () => _showItemEditDialog(item));
                  },
                ),
          ),

          // Action buttons at bottom
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.darkSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.darkBorder),
            ),
            child: Row(children: [
              Expanded(child: SizedBox(height: 52, child: ElevatedButton.icon(
                onPressed: _showUpdateStatusDialog,
                icon: const Icon(Icons.update, size: 22),
                label: const Text('تحديث الحالة', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
              ))),
              const SizedBox(width: 12),
              Expanded(child: SizedBox(height: 52, child: ElevatedButton.icon(
                onPressed: () => _openWhatsApp(phone, customerName),
                icon: const Icon(Icons.chat_rounded, size: 22),
                label: const Text('واتساب', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
              ))),
              if (hasReadyItems) ...[
                const SizedBox(width: 12),
                Expanded(child: SizedBox(height: 52, child: ElevatedButton.icon(
                  onPressed: () async {
                    try {
                      await ref.read(ordersProvider.notifier).updateOrder(widget.orderId, {
                        'status': 'dispatched',
                        'version': _order?['version'],
                      });
                      await _loadOrder();
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ تم إرسال الطلب للتوصيل'), backgroundColor: AppTheme.success));
                    } catch (e) {
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل: $e'), backgroundColor: AppTheme.error));
                    }
                  },
                  icon: const Icon(Icons.local_shipping, size: 22),
                  label: const Text('إرسال للتوصيل', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
                ))),
              ],
            ]),
          ),
        ],
      ),
    );
  }
}

/// Dialog to add a single item to an existing order
class _AddItemDialog extends ConsumerStatefulWidget {
  final String orderId;
  final VoidCallback onAdded;
  const _AddItemDialog({required this.orderId, required this.onAdded});

  @override
  ConsumerState<_AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends ConsumerState<_AddItemDialog> {
  final _productCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _sizeCtrl = TextEditingController();
  final _colorCtrl = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _productCtrl.dispose();
    _urlCtrl.dispose();
    _priceCtrl.dispose();
    _qtyCtrl.dispose();
    _sizeCtrl.dispose();
    _colorCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_productCtrl.text.trim().isEmpty) {
      setState(() => _error = 'اسم المنتج مطلوب');
      return;
    }
    if (_urlCtrl.text.trim().isEmpty) {
      setState(() => _error = 'رابط المنتج مطلوب');
      return;
    }
    setState(() { _isLoading = true; _error = null; });
    try {
      await ref.read(ordersProvider.notifier).addItemToOrder(widget.orderId, {
        'id': const Uuid().v4(),
        'product_name': _productCtrl.text.trim(),
        'product_url': _urlCtrl.text.trim(),
        if (_priceCtrl.text.trim().isNotEmpty) 'unit_price_foreign': double.tryParse(_priceCtrl.text.trim()) ?? 0,
        'quantity': int.tryParse(_qtyCtrl.text.trim()) ?? 1,
        if (_sizeCtrl.text.trim().isNotEmpty) 'size': _sizeCtrl.text.trim(),
        if (_colorCtrl.text.trim().isNotEmpty) 'color': _colorCtrl.text.trim(),
      });
      widget.onAdded();
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('إضافة منتج للطلب', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 4),
            const Text('أدخل تفاصيل المنتج الجديد', style: TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(height: 20),
            if (_error != null) Container(
              padding: const EdgeInsets.all(10), margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: AppTheme.error.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
              child: Text(_error!, style: const TextStyle(color: AppTheme.error, fontSize: 13)),
            ),
            TextField(
              controller: _productCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'اسم المنتج *',
                prefixIcon: Icon(Icons.shopping_bag),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _urlCtrl,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'رابط المنتج / رابط الصورة *',
                hintText: 'https://...',
                hintStyle: TextStyle(color: Colors.white24),
                prefixIcon: Icon(Icons.link),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(
                controller: _priceCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'السعر (اختياري)',
                  prefixIcon: Icon(Icons.attach_money, size: 18),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              )),
              const SizedBox(width: 12),
              SizedBox(width: 80, child: TextField(
                controller: _qtyCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'الكمية',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              )),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(
                controller: _sizeCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'المقاس (اختياري)',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              )),
              const SizedBox(width: 12),
              Expanded(child: TextField(
                controller: _colorCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'اللون (اختياري)',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              )),
            ]),
            const SizedBox(height: 24),
            SizedBox(height: 52, child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _submit,
              icon: _isLoading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.add_shopping_cart, size: 22),
              label: const Text('إضافة المنتج', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            )),
          ]),
        ),
      ),
    );
  }
}

/// Small info chip used in the order header
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: AppTheme.darkCard, borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: Colors.white54),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ]),
    );
  }
}

/// Individual order item card
class _OrderItemCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final Color Function(String) statusColor;
  final String Function(String) translateStatus;
  final VoidCallback? onEditStatus;
  const _OrderItemCard({required this.item, required this.statusColor, required this.translateStatus, this.onEditStatus});

  @override
  Widget build(BuildContext context) {
    final productName = item['product_name'] as String? ?? 'منتج غير معروف';
    final imgUrl = (item['product_image_url'] ?? item['product_thumb_url'] ?? item['product_url'] ?? '').toString();
    final size = item['size'] as String?;
    final color = item['color'] as String?;
    final sku = item['sku'] as String?;
    final itemStatus = (item['status'] ?? 'pending') as String;
    final priceForeign = item['unit_price_foreign'] as num?;
    final priceLocal = item['unit_price_local'] as num?;
    final quantity = (item['quantity'] as num?)?.toInt() ?? 1;
    final productUrl = item['product_url'] as String?;
    final isSorted = itemStatus == 'sorted' || itemStatus == 'ready_dispatch';
    final sColor = statusColor(itemStatus);

    // Determine if imgUrl is a product image or a product link (not a direct image)
    final isDirectImage = imgUrl.isNotEmpty &&
      (imgUrl.endsWith('.jpg') || imgUrl.endsWith('.jpeg') || imgUrl.endsWith('.png') ||
       imgUrl.endsWith('.webp') || imgUrl.endsWith('.gif') || imgUrl.contains('/image/') ||
       imgUrl.contains('r2.') || imgUrl.contains('cloudflare'));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isSorted ? AppTheme.success.withValues(alpha: 0.5) : AppTheme.darkBorder),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Product image or link icon
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 72, height: 72,
            child: isDirectImage
              ? CachedNetworkImage(
                  imageUrl: imgUrl, fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: AppTheme.darkCard, child: const Center(child: CircularProgressIndicator(strokeWidth: 2))),
                  errorWidget: (_, __, ___) => Container(color: AppTheme.darkCard, child: const Icon(Icons.image, color: Colors.white24, size: 32)),
                )
              : productUrl != null && productUrl.isNotEmpty
                ? GestureDetector(
                    onTap: () async {
                      final uri = Uri.tryParse(productUrl);
                      if (uri != null && await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
                    },
                    child: Container(
                      color: AppTheme.primary.withValues(alpha: 0.12),
                      child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.open_in_new, color: AppTheme.primary, size: 28),
                        SizedBox(height: 4),
                        Text('رابط', style: TextStyle(color: AppTheme.primary, fontSize: 10)),
                      ]),
                    ),
                  )
                : Container(color: AppTheme.darkCard, child: const Icon(Icons.image, color: Colors.white24, size: 32)),
          ),
        ),
        const SizedBox(width: 14),
        // Item details
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(productName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15), maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            if (size != null && size.isNotEmpty) _badge(size, AppTheme.secondary),
            if (color != null && color.isNotEmpty) _badge(color, AppTheme.accent),
            if (sku != null && sku.isNotEmpty) _badge('SKU: $sku', AppTheme.primary),
            if (quantity > 1) _badge('×$quantity', Colors.white54),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            if (priceForeign != null) Text('\$${priceForeign.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
            if (priceForeign != null && priceLocal != null) const Text(' / ', style: TextStyle(color: Colors.white38)),
            if (priceLocal != null) Text('${priceLocal.toStringAsFixed(2)} محلي', style: const TextStyle(color: Colors.white54, fontSize: 13)),
          ]),
        ])),
        const SizedBox(width: 10),
        // Status + ready badge + edit
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (onEditStatus != null)
            InkWell(
              onTap: onEditStatus,
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.edit_outlined, color: Colors.white38, size: 16),
              ),
            ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: sColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
            child: Text(translateStatus(itemStatus), style: TextStyle(color: sColor, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
          if (isSorted) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.success.withValues(alpha: 0.5)),
              ),
              child: const Text('جاهز ✓', style: TextStyle(color: AppTheme.success, fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ],
        ]),
      ]),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w500)),
    );
  }
}

// ─── Edit Order Dialog ────────────────────────────────────

class _EditOrderDialog extends StatefulWidget {
  final Map<String, dynamic> order;
  final Future<void> Function(Map<String, dynamic> updates) onSave;
  const _EditOrderDialog({required this.order, required this.onSave});

  @override
  State<_EditOrderDialog> createState() => _EditOrderDialogState();
}

class _EditOrderDialogState extends State<_EditOrderDialog> {
  late final TextEditingController _notesCtrl;
  late final TextEditingController _rateCtrl;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _notesCtrl = TextEditingController(text: widget.order['notes'] as String? ?? '');
    _rateCtrl = TextEditingController(
      text: (widget.order['pegged_exchange_rate'] as num?)?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _rateCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('تعديل الطلب', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 20),
            if (_error != null) Container(
              padding: const EdgeInsets.all(10), margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(color: AppTheme.error.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
              child: Text(_error!, style: const TextStyle(color: AppTheme.error, fontSize: 13)),
            ),
            TextField(
              controller: _notesCtrl,
              style: const TextStyle(color: Colors.white),
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'ملاحظات',
                prefixIcon: Icon(Icons.notes),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _rateCtrl,
              style: const TextStyle(color: Colors.white),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'سعر الصرف المثبت (اختياري)',
                prefixIcon: Icon(Icons.currency_exchange),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(height: 52, child: ElevatedButton.icon(
              onPressed: _saving ? null : () async {
                setState(() { _saving = true; _error = null; });
                final updates = <String, dynamic>{'version': widget.order['version']};
                final notes = _notesCtrl.text.trim();
                if (notes.isNotEmpty) updates['notes'] = notes;
                final rate = double.tryParse(_rateCtrl.text.trim());
                if (rate != null) updates['pegged_exchange_rate'] = rate;
                try {
                  final nav = Navigator.of(context);
                  await widget.onSave(updates);
                  if (mounted) nav.pop();
                } catch (e) {
                  if (mounted) setState(() { _saving = false; _error = e.toString(); });
                }
              },
              icon: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_rounded, size: 22),
              label: const Text('حفظ التغييرات', style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            )),
          ]),
        ),
      ),
    );
  }
}
