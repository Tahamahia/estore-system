import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'package:estore_app/app/theme.dart';
import 'package:estore_app/core/providers.dart';
import 'package:estore_app/core/utils/invoice_generator.dart';
import 'package:printing/printing.dart';

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

  /// Silently re-fetches the order and overwrites local state without showing
  /// a full-screen loading spinner. Used after item edits so the financial
  /// summary rebuilds immediately when the dialog closes.
  Future<void> _refreshOrder() async {
    try {
      final order = await ref.read(ordersProvider.notifier).fetchOrderById(widget.orderId);
      if (mounted) setState(() => _order = order);
    } catch (_) {}
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
    final items = (_order?['items'] as List<dynamic>? ?? [])
        .where((r) => (r as Map<String, dynamic>)['status'] != 'cancelled')
        .toList();
    final orderStatus = _order?['status'] as String? ?? '';
    double totalLocal = 0;
    for (final r in items) {
      final item = r as Map<String, dynamic>;
      final unitLocal = (item['unit_price_local'] as num?)?.toDouble() ?? 0;
      final qty = (item['quantity'] as num?)?.toInt() ?? 1;
      totalLocal += unitLocal * qty;
    }

    final buffer = StringBuffer();
    buffer.writeln('مرحبا $name،');
    buffer.writeln();
    buffer.writeln('تفاصيل طلبك:');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━');
    for (int i = 0; i < items.length; i++) {
      final item = items[i] as Map<String, dynamic>;
      final pName = item['product_name'] as String? ?? 'منتج';
      final qty = (item['quantity'] as num?)?.toInt() ?? 1;
      final size = item['size'] as String?;
      final color = item['color'] as String?;
      final unitLocal = (item['unit_price_local'] as num?)?.toDouble();
      buffer.write('${i + 1}. $pName');
      if (qty > 1) buffer.write(' × $qty');
      buffer.writeln();
      if (size != null && size.isNotEmpty) buffer.writeln('   📐 المقاس: $size');
      if (color != null && color.isNotEmpty) buffer.writeln('   🎨 اللون: $color');
      if (unitLocal != null && unitLocal > 0) {
        final lineTotal = (unitLocal * qty).toStringAsFixed(0);
        buffer.writeln('   💰 ${unitLocal.toStringAsFixed(0)} × $qty = $lineTotal د.ل');
      }
    }
    buffer.writeln('━━━━━━━━━━━━━━━━━━━');
    if (totalLocal > 0) buffer.writeln('الإجمالي: ${totalLocal.toStringAsFixed(0)} د.ل');
    if (orderStatus.isNotEmpty) buffer.writeln('الحالة: ${_translateStatus(orderStatus)}');
    buffer.writeln();
    buffer.writeln('شكراً لتسوقك معنا ✨');

    final url = Uri.parse('https://wa.me/$cleanPhone?text=${Uri.encodeComponent(buffer.toString())}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  void _showInvoiceTypeDialog() {
    final order = _order;
    if (order == null) return;
    final items = order['items'] as List<dynamic>? ?? [];
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppTheme.darkSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('تحميل الفاتورة', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
              const SizedBox(height: 8),
              const Text('اختر نوع الفاتورة', style: TextStyle(color: Colors.white54, fontSize: 14)),
              const SizedBox(height: 24),
              SizedBox(height: 52, child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _downloadInvoice(order, items, InvoiceMode.customer);
                },
                icon: const Icon(Icons.download_outlined, size: 20),
                label: const Text('نسخة الزبون', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
              )),
              const SizedBox(height: 12),
              SizedBox(height: 52, child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _downloadInvoice(order, items, InvoiceMode.merchant);
                },
                icon: const Icon(Icons.download_outlined, size: 20),
                label: const Text('نسخة التاجر', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.secondary),
              )),
            ]),
          ),
        ),
      ),
    );
  }

  /// Generates a PDF and triggers a browser download (or system share sheet on
  /// mobile). Uses Printing.sharePdf which does NOT manipulate the browser
  /// URL/history stack, keeping the user on the Order Detail screen.
  Future<void> _downloadInvoice(Map<String, dynamic> order, List<dynamic> items, InvoiceMode mode) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await InvoiceGenerator.generate(order: order, items: items, mode: mode);
      final rawId = (order['id'] as String?) ?? 'order';
      final shortId = rawId.length >= 8 ? rawId.substring(0, 8).toUpperCase() : rawId.toUpperCase();
      final label = mode == InvoiceMode.customer ? 'Customer' : 'Merchant';
      await Printing.sharePdf(bytes: bytes, filename: 'Invoice_${label}_$shortId.pdf');
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text('فشل تحميل الفاتورة: $e'),
          backgroundColor: AppTheme.error,
        ));
      }
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

  void _showEditItemDialog(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (_) => _EditItemDialog(
        orderId: widget.orderId,
        item: item,
        onSaved: () async {
          // _refreshOrder() silently overwrites _order + calls setState so the
          // FinancialSummaryCard rebuilds the instant the dialog closes.
          await _refreshOrder();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('✅ تم تحديث المنتج'),
              backgroundColor: AppTheme.success,
            ));
          }
        },
      ),
    );
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
          child: StatefulBuilder(builder: (_, setDialogState) {
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
                    onSelected: (v) => setDialogState(() => selectedStatus = s),
                    selectedColor: _statusColor(s),
                    backgroundColor: AppTheme.darkCard,
                    labelStyle: TextStyle(color: selectedStatus == s ? Colors.white : Colors.white70, fontSize: 13),
                  ),
              ]),
              const SizedBox(height: 24),
              SizedBox(height: 52, child: ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await ref.read(ordersProvider.notifier).updateOrder(widget.orderId, {
                      'status': selectedStatus,
                      'version': _order?['version'],
                    });
                    await _loadOrder();
                    if (mounted) {
                      messenger.showSnackBar(SnackBar(
                        content: Text('✅ تم تحديث الحالة إلى ${_translateStatus(selectedStatus)}'),
                        backgroundColor: AppTheme.success,
                      ));
                    }
                  } catch (e) {
                    if (mounted) messenger.showSnackBar(SnackBar(content: Text('فشل: $e'), backgroundColor: AppTheme.error));
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

    return Column(
      children: [
        // Scrollable body — header card + financial summary + items list all scroll together
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Back button + title + edit + print buttons
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
                    icon: const Icon(Icons.print_outlined, color: Colors.white70, size: 22),
                    tooltip: 'طباعة الفاتورة',
                    onPressed: _order != null ? _showInvoiceTypeDialog : null,
                  ),
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
                      _InfoChip(icon: Icons.shopping_bag, label: '${items.fold<int>(0, (sum, raw) => sum + (((raw as Map<String, dynamic>)['quantity'] as num?)?.toInt() ?? 1))} عنصر'),
                    ]),
                  ]),
                ),
                const SizedBox(height: 16),

                // Financial summary
                _FinancialSummaryCard(order: order, items: items),
                const SizedBox(height: 16),

                // Items list header with "Add Item" button
                Row(children: [
                  Text('العناصر (${items.fold<int>(0, (sum, raw) => sum + (((raw as Map<String, dynamic>)['quantity'] as num?)?.toInt() ?? 1))})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _showAddItemDialog,
                    icon: const Icon(Icons.add_circle, color: AppTheme.secondary, size: 20),
                    label: const Text('إضافة منتج', style: TextStyle(color: AppTheme.secondary, fontWeight: FontWeight.w600)),
                  ),
                ]),
                const SizedBox(height: 12),

                // Items — shrinkWrap so the list expands to full height inside the ScrollView
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
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
                    ]),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = items[index] as Map<String, dynamic>;
                      return _OrderItemCard(item: item, statusColor: _statusColor, translateStatus: _translateStatus, onEdit: () => _showEditItemDialog(item));
                    },
                  ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),

        // Action buttons — pinned at the bottom, outside the scroll view
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: BoxDecoration(
            color: AppTheme.darkSurface,
            border: Border(top: BorderSide(color: AppTheme.darkBorder)),
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
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await ref.read(ordersProvider.notifier).updateOrder(widget.orderId, {
                      'status': 'dispatched',
                      'version': _order?['version'],
                    });
                    await _loadOrder();
                    if (mounted) messenger.showSnackBar(const SnackBar(content: Text('✅ تم إرسال الطلب للتوصيل'), backgroundColor: AppTheme.success));
                  } catch (e) {
                    if (mounted) messenger.showSnackBar(SnackBar(content: Text('فشل: $e'), backgroundColor: AppTheme.error));
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
  final _skuCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _shippingCtrl = TextEditingController();
  final _localPriceCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _sizeCtrl = TextEditingController();
  final _colorCtrl = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _productCtrl.dispose();
    _skuCtrl.dispose();
    _urlCtrl.dispose();
    _priceCtrl.dispose();
    _shippingCtrl.dispose();
    _localPriceCtrl.dispose();
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
    setState(() { _isLoading = true; _error = null; });
    try {
      await ref.read(ordersProvider.notifier).addItemToOrder(widget.orderId, {
        'id': const Uuid().v4(),
        'product_name': _productCtrl.text.trim(),
        'sku': _skuCtrl.text.trim(),
        'product_url': _urlCtrl.text.trim(),
        'unit_price_foreign': double.tryParse(_priceCtrl.text.trim()) ?? 0,
        'shipping_cost_foreign': double.tryParse(_shippingCtrl.text.trim()) ?? 0,
        if (_localPriceCtrl.text.trim().isNotEmpty)
          'unit_price_local': double.tryParse(_localPriceCtrl.text.trim()) ?? 0,
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
            const Text('أدخل بيانات المنتج الجديد بالكامل', style: TextStyle(color: Colors.white54, fontSize: 13)),
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
              controller: _skuCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'الرقم التسلسلي (الباركود)',
                prefixIcon: Icon(Icons.qr_code),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _urlCtrl,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'رابط المنتج',
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
                  labelText: 'تكلفة الشراء (\$)',
                  prefixIcon: Icon(Icons.attach_money, size: 18),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              )),
              const SizedBox(width: 10),
              Expanded(child: TextField(
                controller: _shippingCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'تكلفة الشحن (\$)',
                  prefixIcon: Icon(Icons.local_shipping_outlined, size: 18),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              )),
              const SizedBox(width: 10),
              SizedBox(width: 72, child: TextField(
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
            TextField(
              controller: _localPriceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'سعر البيع المحلي (د.ل)',
                prefixIcon: Icon(Icons.sell_outlined, size: 18),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(
                controller: _sizeCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'المقاس',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              )),
              const SizedBox(width: 12),
              Expanded(child: TextField(
                controller: _colorCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'اللون',
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
  final VoidCallback? onEdit;
  const _OrderItemCard({required this.item, required this.statusColor, required this.translateStatus, this.onEdit});

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
    final isCancelled = itemStatus == 'cancelled';
    final isSorted = itemStatus == 'sorted' || itemStatus == 'ready_dispatch';
    final sColor = statusColor(itemStatus);

    // Determine if imgUrl is a product image or a product link (not a direct image)
    final isDirectImage = imgUrl.isNotEmpty &&
      (imgUrl.endsWith('.jpg') || imgUrl.endsWith('.jpeg') || imgUrl.endsWith('.png') ||
       imgUrl.endsWith('.webp') || imgUrl.endsWith('.gif') || imgUrl.contains('/image/') ||
       imgUrl.contains('r2.') || imgUrl.contains('cloudflare'));

    return Opacity(
      opacity: isCancelled ? 0.5 : 1.0,
      child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isCancelled
            ? AppTheme.error.withValues(alpha: 0.4)
            : isSorted ? AppTheme.success.withValues(alpha: 0.5) : AppTheme.darkBorder),
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
          if (onEdit != null)
            InkWell(
              onTap: onEdit,
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
      ),
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
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
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
              controller: _rateCtrl,
              style: const TextStyle(color: Colors.white),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'سعر الصرف المثبت (اختياري)',
                prefixIcon: Icon(Icons.currency_exchange),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _notesCtrl,
              style: const TextStyle(color: Colors.white),
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'ملاحظات',
                prefixIcon: Icon(Icons.notes),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(height: 52, child: ElevatedButton.icon(
              onPressed: _saving ? null : () async {
                setState(() { _saving = true; _error = null; });
                final updates = <String, dynamic>{'version': widget.order['version']};
                final rate = double.tryParse(_rateCtrl.text.trim());
                if (rate != null) updates['pegged_exchange_rate'] = rate;
                final notes = _notesCtrl.text.trim();
                if (notes.isNotEmpty) updates['notes'] = notes;
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

// ─── Financial Summary Card ───────────────────────────────

class _FinancialSummaryCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final List<dynamic> items;
  const _FinancialSummaryCard({required this.order, required this.items});

  @override
  Widget build(BuildContext context) {
    // Sum item-level costs, shipping, and local selling prices, skipping cancelled
    double itemsCostUsd = 0;
    double shippingUsd = 0;
    double totalLocal = 0;
    for (final raw in items) {
      final item = raw as Map<String, dynamic>;
      if ((item['status'] as String?) == 'cancelled') continue;
      final qty = (item['quantity'] as num?)?.toInt() ?? 1;
      itemsCostUsd += ((item['unit_price_foreign'] as num?)?.toDouble() ?? 0) * qty;
      shippingUsd += ((item['shipping_cost_foreign'] as num?)?.toDouble() ?? 0) * qty;
      totalLocal += ((item['unit_price_local'] as num?)?.toDouble() ?? 0) * qty;
    }

    final rate = (order['pegged_exchange_rate'] as num?)?.toDouble() ?? 0;

    final hasPrice = totalLocal > 0;
    final hasRate = rate > 0;
    final profit = (hasPrice && hasRate)
        ? totalLocal - ((itemsCostUsd + shippingUsd) * rate)
        : null;
    final isProfit = profit != null && profit >= 0;

    final borderColor = profit != null
        ? (isProfit ? AppTheme.success : AppTheme.error).withValues(alpha: 0.4)
        : AppTheme.darkBorder;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.calculate_outlined, color: AppTheme.accent, size: 18),
          const SizedBox(width: 8),
          const Text('الملخص المالي', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
        ]),
        const SizedBox(height: 12),
        _FinancialRow(label: 'تكلفة البضاعة (دولار)', value: '\$${itemsCostUsd.toStringAsFixed(2)}'),
        if (shippingUsd > 0) ...[
          const SizedBox(height: 6),
          _FinancialRow(label: 'تكلفة الشحن (دولار)', value: '\$${shippingUsd.toStringAsFixed(2)}'),
        ],
        if (hasRate) ...[
          const SizedBox(height: 6),
          _FinancialRow(label: 'سعر الصرف', value: '${rate.toStringAsFixed(2)} د.ل', dimValue: true),
        ],
        const Divider(height: 20, color: AppTheme.darkBorder),
        if (!hasPrice)
          const Center(
            child: Text('في انتظار تحديد سعر البيع', style: TextStyle(color: Colors.white38, fontSize: 13)),
          )
        else ...[
          _FinancialRow(label: 'سعر البيع (دينار)', value: '${totalLocal.toStringAsFixed(0)} د.ل', bold: true),
          if (profit != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: (isProfit ? AppTheme.success : AppTheme.error).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: (isProfit ? AppTheme.success : AppTheme.error).withValues(alpha: 0.35),
                ),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('المكسب التقديري',
                  style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 14)),
                Text(
                  '${isProfit ? '+' : ''}${profit.toStringAsFixed(0)} د.ل',
                  style: TextStyle(
                    color: isProfit ? AppTheme.success : AppTheme.error,
                    fontWeight: FontWeight.w800, fontSize: 18,
                  ),
                ),
              ]),
            ),
          ],
        ],
      ]),
    );
  }
}

class _FinancialRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final bool dimValue;
  const _FinancialRow({required this.label, required this.value, this.bold = false, this.dimValue = false});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
      Text(value, style: TextStyle(
        color: dimValue ? Colors.white38 : Colors.white70,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        fontSize: bold ? 15 : 14,
      )),
    ]);
  }
}

// ─── Full Item Edit Dialog ────────────────────────────────

class _EditItemDialog extends ConsumerStatefulWidget {
  final String orderId;
  final Map<String, dynamic> item;
  final Future<void> Function() onSaved;
  const _EditItemDialog({required this.orderId, required this.item, required this.onSaved});

  @override
  ConsumerState<_EditItemDialog> createState() => _EditItemDialogState();
}

class _EditItemDialogState extends ConsumerState<_EditItemDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _skuCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _shippingCtrl;
  late final TextEditingController _localPriceCtrl;
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _sizeCtrl;
  late final TextEditingController _colorCtrl;
  late String _selectedStatus;
  bool _saving = false;
  String? _error;

  // (value, Arabic label) pairs for the status dropdown
  static const _statusOptions = [
    ('pending',           'في انتظار الشراء'),
    ('purchased',         'تم الشراء'),
    ('shipped',           'تم الشحن'),
    ('arrived_warehouse', 'وصل المخزن'),
    ('sorted',            'تم الفرز'),
    ('ready_dispatch',    'جاهز للتوصيل'),
    ('dispatched',        'في الطريق'),
    ('delivered',         'تم التوصيل'),
    ('cancelled',         'نفذ من المخزون / ملغي'),
  ];

  @override
  void initState() {
    super.initState();
    _nameCtrl  = TextEditingController(text: widget.item['product_name'] as String? ?? '');
    _skuCtrl   = TextEditingController(text: widget.item['sku']          as String? ?? '');
    _urlCtrl   = TextEditingController(text: widget.item['product_url']  as String? ?? '');
    final price = (widget.item['unit_price_foreign'] as num?)?.toDouble() ?? 0;
    _priceCtrl = TextEditingController(text: price > 0 ? price.toString() : '');
    final shipping = (widget.item['shipping_cost_foreign'] as num?)?.toDouble() ?? 0;
    _shippingCtrl = TextEditingController(text: shipping > 0 ? shipping.toString() : '');
    final localPrice = (widget.item['unit_price_local'] as num?)?.toDouble() ?? 0;
    _localPriceCtrl = TextEditingController(text: localPrice > 0 ? localPrice.toStringAsFixed(0) : '');
    final qty  = (widget.item['quantity'] as num?)?.toInt() ?? 1;
    _qtyCtrl   = TextEditingController(text: qty.toString());
    _sizeCtrl  = TextEditingController(text: widget.item['size']  as String? ?? '');
    _colorCtrl = TextEditingController(text: widget.item['color'] as String? ?? '');
    final rawStatus = (widget.item['status'] as String?) ?? 'pending';
    // Fall back to 'pending' if the status isn't in our dropdown list
    _selectedStatus = _statusOptions.any((o) => o.$1 == rawStatus) ? rawStatus : 'pending';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _skuCtrl.dispose();
    _urlCtrl.dispose();
    _priceCtrl.dispose();
    _shippingCtrl.dispose();
    _localPriceCtrl.dispose();
    _qtyCtrl.dispose();
    _sizeCtrl.dispose();
    _colorCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'اسم المنتج مطلوب');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await ref.read(ordersProvider.notifier).updateOrderItem(
        widget.orderId,
        widget.item['id'] as String,
        {
          'product_name':       name,
          'sku':                _skuCtrl.text.trim(),
          'product_url':        _urlCtrl.text.trim(),
          'unit_price_foreign': double.tryParse(_priceCtrl.text.trim()) ?? 0,
          'shipping_cost_foreign': double.tryParse(_shippingCtrl.text.trim()) ?? 0,
          if (_localPriceCtrl.text.trim().isNotEmpty)
            'unit_price_local': double.tryParse(_localPriceCtrl.text.trim()) ?? 0,
          'quantity':           int.tryParse(_qtyCtrl.text.trim()) ?? 1,
          'size':               _sizeCtrl.text.trim(),
          'color':              _colorCtrl.text.trim(),
          'status':             _selectedStatus,
          'version':            widget.item['version'],
        },
      );
      await widget.onSaved();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCancelled = _selectedStatus == 'cancelled';
    return Dialog(
      backgroundColor: AppTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Header
            Row(children: [
              const Icon(Icons.edit_rounded, color: AppTheme.accent, size: 20),
              const SizedBox(width: 8),
              const Expanded(child: Text('تعديل المنتج',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Colors.white))),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white38),
                onPressed: () => Navigator.of(context).pop(),
                padding: EdgeInsets.zero, constraints: const BoxConstraints(),
              ),
            ]),
            const SizedBox(height: 20),

            if (_error != null) Container(
              padding: const EdgeInsets.all(10), margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: AppTheme.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_error!, style: const TextStyle(color: AppTheme.error, fontSize: 13)),
            ),

            // Status dropdown
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.darkCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isCancelled ? AppTheme.error.withValues(alpha: 0.5) : AppTheme.darkBorder,
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedStatus,
                  isExpanded: true,
                  dropdownColor: AppTheme.darkCard,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  icon: const Icon(Icons.expand_more, color: Colors.white54),
                  items: _statusOptions.map((opt) {
                    final isCancel = opt.$1 == 'cancelled';
                    return DropdownMenuItem(
                      value: opt.$1,
                      child: Text(opt.$2, style: TextStyle(
                        color: isCancel ? AppTheme.error : Colors.white,
                        fontWeight: isCancel ? FontWeight.w600 : FontWeight.normal,
                      )),
                    );
                  }).toList(),
                  onChanged: (v) { if (v != null) setState(() => _selectedStatus = v); },
                ),
              ),
            ),

            if (isCancelled) Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.error.withValues(alpha: 0.25)),
              ),
              child: const Row(children: [
                Icon(Icons.info_outline, color: AppTheme.error, size: 15),
                SizedBox(width: 8),
                Expanded(child: Text(
                  'هذا المنتج سيُستثنى من حساب التكلفة والتوصيل',
                  style: TextStyle(color: AppTheme.error, fontSize: 12),
                )),
              ]),
            ),

            const SizedBox(height: 14),

            // Product name
            TextField(
              controller: _nameCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'اسم المنتج *',
                prefixIcon: Icon(Icons.shopping_bag),
              ),
            ),
            const SizedBox(height: 12),

            // SKU / barcode
            TextField(
              controller: _skuCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'الرقم التسلسلي (الباركود)',
                prefixIcon: Icon(Icons.qr_code),
              ),
            ),
            const SizedBox(height: 12),

            // URL
            TextField(
              controller: _urlCtrl,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'رابط المنتج',
                hintText: 'https://...',
                hintStyle: TextStyle(color: Colors.white24),
                prefixIcon: Icon(Icons.link),
              ),
            ),
            const SizedBox(height: 12),

            // Financial fields: purchase price + shipping + quantity
            Row(children: [
              Expanded(child: TextField(
                controller: _priceCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'تكلفة الشراء (\$)',
                  prefixIcon: Icon(Icons.attach_money, size: 18),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              )),
              const SizedBox(width: 10),
              Expanded(child: TextField(
                controller: _shippingCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'تكلفة الشحن (\$)',
                  prefixIcon: Icon(Icons.local_shipping_outlined, size: 18),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              )),
              const SizedBox(width: 10),
              SizedBox(width: 72, child: TextField(
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

            // Local selling price
            TextField(
              controller: _localPriceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'سعر البيع المحلي (د.ل)',
                prefixIcon: Icon(Icons.sell_outlined, size: 18),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
            const SizedBox(height: 12),

            // Size + color
            Row(children: [
              Expanded(child: TextField(
                controller: _sizeCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'المقاس',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              )),
              const SizedBox(width: 12),
              Expanded(child: TextField(
                controller: _colorCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'اللون',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              )),
            ]),
            const SizedBox(height: 24),

            SizedBox(height: 52, child: ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_rounded, size: 22),
              label: const Text('حفظ التغييرات', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            )),
          ]),
        ),
      ),
    );
  }
}
