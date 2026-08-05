import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'package:estore_app/app/theme.dart';
import 'package:estore_app/core/providers.dart';
import 'package:estore_app/core/utils/dialog_utils.dart';
import 'package:estore_app/core/utils/invoice_generator.dart';
import 'package:printing/printing.dart';

double _parseDouble(String text) =>
    double.tryParse(text.trim().replaceAll(',', '.')) ?? 0;

/// Extracts the clean human-readable message from a DioException.
/// Reads e.response?.data directly — never falls back to e.message or
/// e.toString() which both contain the verbose "DioException [bad response]:"
/// prefix injected by Dio 5.x.
String _dioMsg(DioException e) {
  final data = e.response?.data;
  if (data is Map<String, dynamic>) {
    return data['message'] as String? ?? data['error'] as String? ?? 'حدث خطأ غير معروف';
  }
  return data?.toString() ?? 'فشل الاتصال بالخادم';
}

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
  bool _orphanLoading = false;
  bool _dispatchLoading = false;
  String? _error;
  final Set<String> _selectedItemIds = {};

  @override
  void initState() {
    super.initState();
    _loadOrder();
  }

  Future<void> _loadOrder() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final order = await ref.read(ordersProvider.notifier).fetchOrderById(widget.orderId);
      if (!mounted) return;
      setState(() { _order = order; _loading = false; _selectedItemIds.clear(); });
    } catch (e) {
      if (!mounted) return;
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
      case 'pending':                  return 'في انتظار الشراء';
      case 'purchased':                return 'تم الشراء';
      case 'shipped':                  return 'تم الشحن';
      case 'arrived_warehouse':        return 'وصل المخزن';
      case 'sorted':                   return 'تم الفرز';
      case 'ready_dispatch':           return 'جاهز للتوصيل';
      case 'dispatched':               return 'في الطريق';
      case 'delivered':                return 'تم التوصيل';
      case 'cancelled':                return 'ملغي';
      case 'refunded':                 return 'مُسترد';
      case 'transferred_to_inventory': return 'محوّل للمخزون';
      case 'in_stock':                 return 'فوري';
      default: return status.replaceAll('_', ' ');
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pending': return AppTheme.warning;
      case 'purchased':
      case 'shipped': return AppTheme.secondary;
      case 'arrived_warehouse':
      case 'sorted': return AppTheme.accent;
      case 'ready_dispatch': return AppTheme.success;
      case 'dispatched': return const Color(0xFF3B82F6);
      case 'delivered': return AppTheme.success;
      case 'refunded':
      case 'transferred_to_inventory':
      case 'in_stock': return Colors.orange;
      case 'cancelled': return AppTheme.error;
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
        insetPadding: EdgeInsets.symmetric(horizontal: isMobile(ctx) ? 8 : 40, vertical: 24),
        backgroundColor: AppTheme.darkSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: dialogMaxWidth(ctx, desktopMax: 360)),
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
    final dialog = _EditItemDialog(
      orderId: widget.orderId,
      order: _order!,
      item: item,
      onSaved: () async {
        await _refreshOrder();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('✅ تم تحديث المنتج'),
            backgroundColor: AppTheme.success,
          ));
        }
      },
    );
    if (isMobile(context)) {
      Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => dialog));
    } else {
      showDialog(context: context, builder: (_) => dialog);
    }
  }

  void _showAddItemDialog() {
    final dialog = _AddItemDialog(
      orderId: widget.orderId,
      order: _order!,
      onAdded: () async {
        await _loadOrder();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('✅ تم إضافة المنتج للطلب'),
            backgroundColor: AppTheme.success,
          ));
        }
      },
    );
    if (isMobile(context)) {
      Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => dialog));
    } else {
      showDialog(context: context, builder: (_) => dialog);
    }
  }

  Future<void> _orphanItems() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (orphanCtx) => AlertDialog(
        backgroundColor: AppTheme.darkSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('إلغاء وتحويل للفوري', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: const Text(
          'سيتم إلغاء هذه الطلبية وتحويل منتجاتها إلى مخزون البضاعة الفورية.\nتكاليف الشراء تُسجَّل كخسارة في التسوية.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(orphanCtx).pop(false),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.of(orphanCtx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.warning),
            child: const Text('تحويل للفوري'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirm != true) return;
    setState(() => _orphanLoading = true);
    try {
      await ref.read(ordersProvider.notifier).orphanOrderItems(widget.orderId);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      await _loadOrder();
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
        content: Text('تم إلغاء الطلبية وتحويل المنتجات للفوري'),
        backgroundColor: AppTheme.success,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: AppTheme.error));
    } finally {
      if (mounted) setState(() => _orphanLoading = false);
    }
  }

  /// Splits the order by moving [selectedIds] into a new child order.
  void _showSplitOrderDialog(Set<String> selectedIds, Set<String> allSelectableIds) {
    final movedCount = selectedIds.intersection(allSelectableIds).length;
    final remainingCount = allSelectableIds.length - movedCount;
    final isFullCart = (_order?['order_type'] as String?) == 'full_cart';
    final salePriceCtrl = TextEditingController();
    final costUsdCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (splitCtx) => Dialog(
        insetPadding: EdgeInsets.symmetric(horizontal: isMobile(splitCtx) ? 8 : 40, vertical: 24),
        backgroundColor: AppTheme.darkSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: dialogMaxWidth(splitCtx, desktopMax: 420)),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: StatefulBuilder(builder: (_, setDialogState) {
              return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  const Icon(Icons.call_split, color: AppTheme.secondary, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(child: Text(
                    'تقسيم الطلبية',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
                  )),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white38),
                    onPressed: () => Navigator.of(splitCtx).pop(),
                    padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                  ),
                ]),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.secondary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.secondary.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    'سيتم نقل $movedCount منتج إلى طلبية جديدة، وستبقى $remainingCount منتج في الطلبية الحالية.',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ),
                if (isFullCart) ...[
                  const SizedBox(height: 20),
                  TextField(
                    controller: salePriceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'سعر البيع للقطع المنقولة (د.ل)',
                      labelStyle: const TextStyle(color: Colors.white54),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: AppTheme.darkBorder),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: AppTheme.primary),
                        borderRadius: BorderRadius.all(Radius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: costUsdCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'تكلفة الشراء للقطع المنقولة (دولار) — اختياري',
                      labelStyle: const TextStyle(color: Colors.white54),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: AppTheme.darkBorder),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: AppTheme.primary),
                        borderRadius: BorderRadius.all(Radius.circular(10)),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Row(children: [
                  Expanded(child: SizedBox(height: 44, child: OutlinedButton(
                    onPressed: () => Navigator.of(splitCtx).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white54,
                      side: BorderSide(color: AppTheme.darkBorder),
                    ),
                    child: const Text('إلغاء'),
                  ))),
                  const SizedBox(width: 12),
                  Expanded(child: SizedBox(height: 44, child: ElevatedButton(
                    onPressed: () async {
                      if (isFullCart) {
                        final parsed = double.tryParse(salePriceCtrl.text.trim().replaceAll(',', '.'));
                        if (parsed == null) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text('يجب إدخال سعر البيع للقطع المنقولة'),
                            backgroundColor: AppTheme.error,
                          ));
                          return;
                        }
                      }
                      Navigator.of(splitCtx).pop();
                      if (!mounted) return;
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        final movedSalePrice = isFullCart
                            ? double.tryParse(salePriceCtrl.text.trim().replaceAll(',', '.'))
                            : null;
                        final movedCost = isFullCart
                            ? double.tryParse(costUsdCtrl.text.trim().replaceAll(',', '.'))
                            : null;
                        final newOrderId = await ref.read(ordersProvider.notifier).splitOrder(
                          widget.orderId,
                          selectedIds.toList(),
                          movedSalePriceLyd: movedSalePrice,
                          movedCostUsd: movedCost,
                        );
                        if (!mounted) return;
                        setState(() => _selectedItemIds.clear());
                        await _loadOrder();
                        if (!mounted) return;
                        messenger.showSnackBar(SnackBar(
                          content: const Text('✅ تم إنشاء الطلبية الجديدة'),
                          backgroundColor: AppTheme.success,
                          action: SnackBarAction(
                            label: 'فتح الطلبية الجديدة',
                            textColor: Colors.white,
                            onPressed: () => context.go('/orders/$newOrderId'),
                          ),
                        ));
                      } on DioException catch (e) {
                        if (!mounted) return;
                        messenger.showSnackBar(SnackBar(
                          content: Text('فشل: ${_dioMsg(e)}'),
                          backgroundColor: AppTheme.error,
                        ));
                      } catch (e) {
                        if (!mounted) return;
                        messenger.showSnackBar(SnackBar(
                          content: Text('فشل: ${e.toString()}'),
                          backgroundColor: AppTheme.error,
                        ));
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.secondary),
                    child: const Text('تأكيد التقسيم', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ))),
                ]),
              ]);
            }),
          ),
        ),
      ),
    ).then((_) {
      salePriceCtrl.dispose();
      costUsdCtrl.dispose();
    });
  }

  /// Opens a status-chip dialog and PATCHes only the items in [_selectedItemIds].
  void _showBulkItemStatusDialog() {
    if (_selectedItemIds.isEmpty) return;
    const validItemStatuses = [
      'pending', 'purchased', 'shipped', 'arrived_warehouse',
      'sorted', 'ready_dispatch', 'dispatched', 'delivered', 'cancelled',
    ];
    String selectedStatus = validItemStatuses.first;
    showDialog(
      context: context,
      builder: (bulkCtx) => Dialog(
        insetPadding: EdgeInsets.symmetric(horizontal: isMobile(bulkCtx) ? 8 : 40, vertical: 24),
        backgroundColor: AppTheme.darkSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: dialogMaxWidth(bulkCtx, desktopMax: 420)),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: StatefulBuilder(builder: (_, setDialogState) {
              return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  const Icon(Icons.check_box_outlined, color: AppTheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    'تحديث ${_selectedItemIds.length} عنصر محدد',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
                  )),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white38),
                    onPressed: () => Navigator.of(bulkCtx).pop(),
                    padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                  ),
                ]),
                const SizedBox(height: 6),
                const Text('اختر الحالة الجديدة للعناصر المحددة', style: TextStyle(color: Colors.white54, fontSize: 13)),
                const SizedBox(height: 20),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final s in validItemStatuses)
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
                SizedBox(height: 48, child: ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.of(bulkCtx).pop();
                    if (!mounted) return;
                    final messenger = ScaffoldMessenger.of(context);
                    final targetIds = Set<String>.from(_selectedItemIds);
                    final allItems = (_order?['items'] as List<dynamic>? ?? [])
                        .map((r) => r as Map<String, dynamic>)
                        .where((item) => targetIds.contains(item['id'] as String?))
                        .toList();
                    final successIds = <String>{};
                    for (final item in allItems) {
                      try {
                        await ref.read(ordersProvider.notifier).updateOrderItem(
                          widget.orderId,
                          item['id'] as String,
                          {'status': selectedStatus, 'version': item['version']},
                        );
                        successIds.add(item['id'] as String);
                      } catch (_) {}
                    }
                    if (!mounted) return;
                    if (successIds.isNotEmpty) {
                      setState(() {
                        if (_order == null) return;
                        final o = Map<String, dynamic>.from(_order!);
                        o['items'] = (o['items'] as List<dynamic>).map((raw) {
                          final itm = Map<String, dynamic>.from(raw as Map<String, dynamic>);
                          if (successIds.contains(itm['id'] as String?)) {
                            itm['status'] = selectedStatus;
                            itm['version'] = ((itm['version'] as num?)?.toInt() ?? 0) + 1;
                          }
                          return itm;
                        }).toList();
                        _order = o;
                        _selectedItemIds.clear();
                      });
                    }
                    final failed = targetIds.length - successIds.length;
                    messenger.showSnackBar(SnackBar(
                      content: Text(failed == 0
                          ? '✅ تم تحديث ${successIds.length} عنصر إلى "${_translateStatus(selectedStatus)}"'
                          : '✅ ${successIds.length} نجح، $failed فشل — تحقق من أرقام الإصدار'),
                      backgroundColor: failed == 0 ? AppTheme.success : AppTheme.warning,
                    ));
                  },
                  icon: const Icon(Icons.check, size: 20),
                  label: const Text('تحديث', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
                )),
              ]);
            }),
          ),
        ),
      ),
    );
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
    final phone2 = order['customer_phone2'] as String?;
    final city = order['customer_city'] as String?;
    final area = order['customer_area'] as String?;
    final street = order['customer_street'] as String?;
    final locationUrl = order['customer_location_url'] as String?;
    final platform = order['platform'] as String? ?? 'Manual';
    final createdAt = order['created_at'] as String? ?? '';
    final items = order['items'] as List<dynamic>? ?? [];
    final cartLink = order['cart_link'] as String?;
    final hasReadyItems = items.any((item) {
      final s = (item as Map<String, dynamic>)['status'] as String? ?? '';
      return s == 'sorted' || s == 'ready_dispatch';
    });

    return Column(
      children: [
        // Scrollable body — header + financial summary + items list scroll together
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Back button + title + edit + print
                Row(children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 28),
                    onPressed: () {
                      if (context.canPop()) { context.pop(); } else { context.go('/orders'); }
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'تفاصيل الطلب',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: AppTheme.primary.withValues(alpha: 0.2),
                          child: Text(
                            customerName.isNotEmpty ? customerName[0] : '?',
                            style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700, fontSize: 20),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
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
                              if (phone2 != null && phone2.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                GestureDetector(
                                  onTap: () => _callPhone(phone2),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    const Icon(Icons.phone_outlined, color: AppTheme.secondary, size: 15),
                                    const SizedBox(width: 6),
                                    Text(phone2, style: const TextStyle(color: AppTheme.secondary, fontSize: 13, decoration: TextDecoration.underline)),
                                  ]),
                                ),
                              ],
                              Builder(builder: (_) {
                                final parts = [city, area, street].where((p) => p != null && p.isNotEmpty).toList();
                                if (parts.isEmpty) return const SizedBox.shrink();
                                return Padding(
                                  padding: const EdgeInsets.only(top: 5),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    const Icon(Icons.location_on_outlined, color: Colors.white38, size: 15),
                                    const SizedBox(width: 5),
                                    Flexible(child: Text(parts.join(' - '), style: const TextStyle(color: Colors.white54, fontSize: 12))),
                                    if (locationUrl != null && locationUrl.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 6),
                                        child: InkWell(
                                          onTap: () async {
                                            final uri = Uri.tryParse(locationUrl);
                                            if (uri != null && await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
                                          },
                                          child: const Icon(Icons.open_in_new, color: AppTheme.primary, size: 15),
                                        ),
                                      ),
                                  ]),
                                );
                              }),
                              if ((city == null || city.isEmpty) && (area == null || area.isEmpty) && (street == null || street.isEmpty) && locationUrl != null && locationUrl.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 5),
                                  child: InkWell(
                                    onTap: () async {
                                      final uri = Uri.tryParse(locationUrl);
                                      if (uri != null && await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
                                    },
                                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                      Icon(Icons.location_on, color: AppTheme.primary, size: 15),
                                      SizedBox(width: 4),
                                      Text('عرض اللوكيشن', style: TextStyle(color: AppTheme.primary, fontSize: 12, decoration: TextDecoration.underline)),
                                    ]),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: _statusColor(status).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: _statusColor(status).withValues(alpha: 0.4)),
                            ),
                            child: Text(
                              _translateStatus(status),
                              style: TextStyle(color: _statusColor(status), fontSize: 14, fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Tooltip(
                            message: 'تُحسب تلقائياً من حالة المنتجات',
                            child: const Icon(Icons.info_outline, size: 13, color: Colors.white38),
                          ),
                        ]),
                      ]),
                      const SizedBox(height: 12),
                      Row(children: [
                        _InfoChip(icon: Icons.storefront, label: platform),
                        const SizedBox(width: 12),
                        if (createdAt.isNotEmpty)
                          _InfoChip(icon: Icons.calendar_today, label: createdAt.length > 10 ? createdAt.substring(0, 10) : createdAt),
                        const SizedBox(width: 12),
                        _InfoChip(
                          icon: Icons.shopping_bag,
                          label: '${items.fold<int>(0, (sum, raw) => sum + (((raw as Map<String, dynamic>)['quantity'] as num?)?.toInt() ?? 1))} عنصر',
                        ),
                      ]),
                      if (cartLink != null && cartLink.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: () async {
                            final uri = Uri.tryParse(cartLink);
                            if (uri != null && await canLaunchUrl(uri)) {
                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.shopping_cart_outlined, color: AppTheme.primary, size: 14),
                              const SizedBox(width: 6),
                              Flexible(child: Text(
                                cartLink,
                                style: const TextStyle(color: AppTheme.primary, fontSize: 12, decoration: TextDecoration.underline),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              )),
                              const SizedBox(width: 4),
                              const Icon(Icons.open_in_new, color: AppTheme.primary, size: 12),
                            ]),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Parent / child order links
                Builder(builder: (_) {
                  final parentId = order['parent_order_id'] as String?;
                  final childOrders = (order['child_orders'] as List<dynamic>?)
                      ?.map((r) => r as Map<String, dynamic>)
                      .toList();
                  if (parentId == null && (childOrders == null || childOrders.isEmpty)) {
                    return const SizedBox.shrink();
                  }
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (parentId != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppTheme.warning.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.warning.withValues(alpha: 0.25)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.account_tree_outlined, color: AppTheme.warning, size: 16),
                          const SizedBox(width: 8),
                          const Expanded(child: Text(
                            'هذه الطلبية جزء من طلبية أصلية',
                            style: TextStyle(color: Colors.white70, fontSize: 13),
                          )),
                          ActionChip(
                            label: Text(
                              parentId.length >= 8 ? parentId.substring(0, 8).toUpperCase() : parentId,
                              style: const TextStyle(color: AppTheme.primary, fontSize: 12),
                            ),
                            backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                            side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.3)),
                            onPressed: () => context.go('/orders/$parentId'),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            visualDensity: VisualDensity.compact,
                          ),
                        ]),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (childOrders != null && childOrders.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppTheme.secondary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.secondary.withValues(alpha: 0.25)),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            const Icon(Icons.call_split, color: AppTheme.secondary, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              '${childOrders.length} طلبية فرعية',
                              style: const TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                          ]),
                          const SizedBox(height: 8),
                          Wrap(spacing: 8, runSpacing: 6, children: [
                            for (final child in childOrders) ...[
                              ActionChip(
                                label: Row(mainAxisSize: MainAxisSize.min, children: [
                                  Text(
                                    (child['id'] as String).length >= 8
                                        ? (child['id'] as String).substring(0, 8).toUpperCase()
                                        : child['id'] as String,
                                    style: const TextStyle(color: Colors.white, fontSize: 11),
                                  ),
                                  const SizedBox(width: 5),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: _statusColor(child['status'] as String? ?? 'pending').withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      _translateStatus(child['status'] as String? ?? 'pending'),
                                      style: TextStyle(
                                        color: _statusColor(child['status'] as String? ?? 'pending'),
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                ]),
                                backgroundColor: AppTheme.darkCard,
                                side: BorderSide(color: AppTheme.secondary.withValues(alpha: 0.3)),
                                onPressed: () => context.go('/orders/${child['id']}'),
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ]),
                        ]),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ]);
                }),

                // Financial summary
                _FinancialSummaryCard(order: order, items: items),
                const SizedBox(height: 16),

                // Build selection state derived from current items
                ...() {
                  final selectableIds = items
                      .map((r) => (r as Map<String, dynamic>)['id'] as String?)
                      .whereType<String>()
                      .toSet();
                  final allSelected = selectableIds.isNotEmpty &&
                      selectableIds.every(_selectedItemIds.contains);
                  final noneSelected = _selectedItemIds.isEmpty ||
                      !selectableIds.any(_selectedItemIds.contains);

                  return [
                    // ── Items list header ──────────────────────────────────
                    Row(children: [
                      if (items.isNotEmpty) ...[
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: Checkbox(
                            tristate: true,
                            value: allSelected ? true : (noneSelected ? false : null),
                            onChanged: (v) => setState(() {
                              if (v == true) { _selectedItemIds.addAll(selectableIds); }
                              else { _selectedItemIds.removeAll(selectableIds); }
                            }),
                            activeColor: AppTheme.primary,
                            checkColor: Colors.white,
                            side: const BorderSide(color: Colors.white38, width: 1.5),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        'العناصر (${items.fold<int>(0, (sum, raw) => sum + (((raw as Map<String, dynamic>)['quantity'] as num?)?.toInt() ?? 1))})',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _showAddItemDialog,
                        icon: const Icon(Icons.add_circle, color: AppTheme.secondary, size: 20),
                        label: const Text('إضافة منتج', style: TextStyle(color: AppTheme.secondary, fontWeight: FontWeight.w600)),
                      ),
                    ]),

                    // ── Bulk action bar — visible when items are selected ──
                    if (_selectedItemIds.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.35)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.check_box_outlined, color: AppTheme.primary, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            '${_selectedItemIds.intersection(selectableIds).length} محدد',
                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => setState(() => _selectedItemIds.removeAll(selectableIds)),
                            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)),
                            child: const Text('إلغاء', style: TextStyle(color: Colors.white54, fontSize: 13)),
                          ),
                          const SizedBox(width: 4),
                          SizedBox(height: 36, child: ElevatedButton.icon(
                            onPressed: _showBulkItemStatusDialog,
                            icon: const Icon(Icons.update, size: 16),
                            label: const Text('تحديث الحالة', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                            ),
                          )),
                          const SizedBox(width: 6),
                          Builder(builder: (_) {
                            final canSplit = _selectedItemIds.intersection(selectableIds).length < selectableIds.length;
                            return Tooltip(
                              message: canSplit ? '' : 'لازم يبقى منتج واحد على الأقل',
                              child: SizedBox(height: 36, child: ElevatedButton.icon(
                                onPressed: canSplit
                                    ? () => _showSplitOrderDialog(
                                          Set<String>.from(_selectedItemIds.intersection(selectableIds)),
                                          selectableIds,
                                        )
                                    : null,
                                icon: const Icon(Icons.call_split, size: 16),
                                label: const Text('تقسيم', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.secondary,
                                  disabledBackgroundColor: AppTheme.secondary.withValues(alpha: 0.3),
                                  padding: const EdgeInsets.symmetric(horizontal: 14),
                                ),
                              )),
                            );
                          }),
                        ]),
                      ),
                    ],
                    const SizedBox(height: 12),

                    // ── Items list ─────────────────────────────────────────
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
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                            ),
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
                          final itemId = item['id'] as String? ?? '';
                          return _OrderItemCard(
                            item: item,
                            statusColor: _statusColor,
                            translateStatus: _translateStatus,
                            selected: _selectedItemIds.contains(itemId),
                            onToggle: itemId.isNotEmpty ? (v) => setState(() {
                              if (v == true) { _selectedItemIds.add(itemId); }
                              else { _selectedItemIds.remove(itemId); }
                            }) : null,
                            onEdit: () => _showEditItemDialog(item),
                          );
                        },
                      ),
                  ];
                }(),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),

        // Action buttons — pinned at bottom, outside the scroll view
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: BoxDecoration(
            color: AppTheme.darkSurface,
            border: Border(top: BorderSide(color: AppTheme.darkBorder)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (!const ['delivered', 'cancelled', 'refunded', 'transferred_to_inventory', 'in_stock'].contains(status)) ...[
              SizedBox(
                height: 46,
                child: OutlinedButton.icon(
                  onPressed: _orphanLoading ? null : _orphanItems,
                  icon: _orphanLoading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.warning))
                    : const Icon(Icons.inventory_2_outlined, size: 18),
                  label: const Text('إلغاء وتحويل لفوري', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.warning,
                    side: BorderSide(color: AppTheme.warning.withValues(alpha: 0.5)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Row(children: [
              Expanded(child: SizedBox(height: 52, child: ElevatedButton.icon(
                onPressed: () => _openWhatsApp(phone, customerName),
                icon: const Icon(Icons.chat_rounded, size: 22),
                label: const Text('واتساب', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
              ))),
              if (hasReadyItems) ...[
                const SizedBox(width: 12),
                Expanded(child: SizedBox(height: 52, child: ElevatedButton.icon(
                  onPressed: _dispatchLoading ? null : () async {
                    setState(() => _dispatchLoading = true);
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      final readyItems = (_order?['items'] as List<dynamic>? ?? [])
                          .map((r) => r as Map<String, dynamic>)
                          .where((item) {
                            final s = item['status'] as String? ?? '';
                            return s == 'sorted' || s == 'ready_dispatch';
                          })
                          .toList();
                      for (final item in readyItems) {
                        await ref.read(ordersProvider.notifier).updateOrderItem(
                          widget.orderId, item['id'] as String,
                          {'status': 'dispatched', 'version': item['version']},
                        );
                      }
                      if (!mounted) return;
                      await _loadOrder();
                      if (!mounted) return;
                      messenger.showSnackBar(const SnackBar(
                        content: Text('✅ تم إرسال الطلب للتوصيل'),
                        backgroundColor: AppTheme.success,
                      ));
                    } on DioException catch (e) {
                      if (!mounted) return;
                      messenger.showSnackBar(SnackBar(content: Text('فشل: ${_dioMsg(e)}'), backgroundColor: AppTheme.error));
                    } catch (e) {
                      if (!mounted) return;
                      messenger.showSnackBar(SnackBar(content: Text('فشل: ${e.toString()}'), backgroundColor: AppTheme.error));
                    } finally {
                      if (mounted) setState(() => _dispatchLoading = false);
                    }
                  },
                  icon: _dispatchLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.local_shipping, size: 22),
                  label: const Text('إرسال للتوصيل', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
                ))),
              ],
            ]),
          ]),
        ),
      ],
    );
  }
}

/// Dialog to add a single item to an existing order
class _AddItemDialog extends ConsumerStatefulWidget {
  final String orderId;
  final Map<String, dynamic> order;
  final VoidCallback onAdded;
  const _AddItemDialog({required this.orderId, required this.order, required this.onAdded});

  @override
  ConsumerState<_AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends ConsumerState<_AddItemDialog> {
  final _productCtrl = TextEditingController();
  final _skuCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _localPriceCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _sizeCtrl = TextEditingController();
  final _colorCtrl = TextEditingController();
  final _brandCtrl = TextEditingController();
  String? _selectedCategory;
  String? _selectedSourceName;
  double _currentShippingRate = 0;
  bool _isLoading = false;
  String? _error;

  static const _categories = ['Clothes', 'Electronic', 'Accessories', 'Other'];

  @override
  void initState() {
    super.initState();
    _weightCtrl.addListener(() => setState(() {}));
    _qtyCtrl.addListener(() => setState(() {}));
    Future.microtask(() => ref.read(shippingSourcesProvider.notifier).fetchSources());
  }

  @override
  void dispose() {
    _productCtrl.dispose();
    _skuCtrl.dispose();
    _urlCtrl.dispose();
    _priceCtrl.dispose();
    _weightCtrl.dispose();
    _localPriceCtrl.dispose();
    _qtyCtrl.dispose();
    _sizeCtrl.dispose();
    _colorCtrl.dispose();
    _brandCtrl.dispose();
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
        if (_skuCtrl.text.trim().isNotEmpty) 'sku': _skuCtrl.text.trim(),
        if (_urlCtrl.text.trim().isNotEmpty) 'product_url': _urlCtrl.text.trim(),
        'unit_price_foreign': _parseDouble(_priceCtrl.text),
        'weight': _parseDouble(_weightCtrl.text),
        'shipping_rate_per_kg': _currentShippingRate,
        if (_selectedSourceName != null) 'source_name': _selectedSourceName,
        if (_localPriceCtrl.text.trim().isNotEmpty)
          'unit_price_local': _parseDouble(_localPriceCtrl.text),
        'quantity': int.tryParse(_qtyCtrl.text.trim()) ?? 1,
        if (_selectedCategory != null) 'item_category': _selectedCategory,
        if (_sizeCtrl.text.trim().isNotEmpty) 'size': _sizeCtrl.text.trim(),
        if (_colorCtrl.text.trim().isNotEmpty) 'color': _colorCtrl.text.trim(),
        if (_brandCtrl.text.trim().isNotEmpty) 'brand': _brandCtrl.text.trim(),
      });
      widget.onAdded();
      if (mounted) { Navigator.of(context).pop(); }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is DioException
              ? _dioMsg(e)
              : e.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sourcesState = ref.watch(shippingSourcesProvider);
    final sources = sourcesState.valueOrNull ?? [];
    final weight = _parseDouble(_weightCtrl.text);
    final qty = int.tryParse(_qtyCtrl.text.trim()) ?? 1;
    final calcShipping = weight * _currentShippingRate * qty;
    final showClothesFields = _selectedCategory == 'Clothes';
    final showBrandField = _selectedCategory == 'Electronic' || _selectedCategory == 'Accessories';

    final formContent = _buildAddItemFormContent(
      sources: sources,
      weight: weight,
      qty: qty,
      calcShipping: calcShipping,
      showClothesFields: showClothesFields,
      showBrandField: showBrandField,
    );
    final submitButton = SizedBox(height: 52, child: ElevatedButton.icon(
      onPressed: _isLoading ? null : _submit,
      icon: _isLoading
        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
        : const Icon(Icons.add_shopping_cart, size: 22),
      label: const Text('إضافة المنتج', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
    ));

    if (isMobile(context)) {
      return Scaffold(
        backgroundColor: AppTheme.darkSurface,
        appBar: AppBar(
          backgroundColor: AppTheme.darkSurface,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white38),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text('إضافة منتج للطلب', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: formContent,
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: submitButton,
          ),
        ),
      );
    }

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      backgroundColor: AppTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: dialogMaxWidth(context, desktopMax: 520), maxHeight: dialogMaxHeight(context)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            formContent,
            const SizedBox(height: 24),
            submitButton,
          ]),
        ),
      ),
    );
  }

  Widget _buildAddItemFormContent({
    required List<Map<String, dynamic>> sources,
    required double weight,
    required int qty,
    required double calcShipping,
    required bool showClothesFields,
    required bool showBrandField,
  }) {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('إضافة منتج للطلب', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
      const SizedBox(height: 4),
      const Text('أدخل بيانات المنتج الجديد بالكامل', style: TextStyle(color: Colors.white54, fontSize: 13)),
      const SizedBox(height: 20),
      if (_error != null) Container(
        padding: const EdgeInsets.all(10), margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(color: AppTheme.error.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
        child: Text(_error!, style: const TextStyle(color: AppTheme.error, fontSize: 13)),
      ),
      // ── Section 1: تفاصيل المنتج ─────────────────────────────
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.darkCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('تفاصيل المنتج', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white70)),
          const SizedBox(height: 12),
          TextField(
            controller: _productCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'اسم المنتج *',
              prefixIcon: Icon(Icons.shopping_bag_outlined),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _skuCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'الرقم التسلسلي (الباركود)',
              prefixIcon: Icon(Icons.qr_code),
            ),
          ),
          const SizedBox(height: 10),
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
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _selectedCategory,
            dropdownColor: AppTheme.darkCard,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'فئة المنتج',
              prefixIcon: Icon(Icons.category_outlined),
            ),
            items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
            onChanged: (v) => setState(() { _selectedCategory = v; _sizeCtrl.clear(); _colorCtrl.clear(); _brandCtrl.clear(); }),
          ),
          if (showClothesFields) ...[
            const SizedBox(height: 10),
            LayoutBuilder(builder: (context, constraints) {
              final sizeField = TextField(
                controller: _sizeCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'المقاس', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
              );
              final colorField = TextField(
                controller: _colorCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'اللون', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
              );
              if (constraints.maxWidth < 400) {
                return Column(children: [sizeField, const SizedBox(height: 8), colorField]);
              }
              return Row(children: [Expanded(child: sizeField), const SizedBox(width: 10), Expanded(child: colorField)]);
            }),
          ] else if (showBrandField) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _brandCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'الماركة (Brand)',
                prefixIcon: Icon(Icons.branding_watermark_outlined),
              ),
            ),
          ],
        ]),
      ),
      const SizedBox(height: 14),
      // ── Section 2: التفاصيل المالية ──────────────────────────
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.darkCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('التفاصيل المالية', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white70)),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, constraints) {
            final priceField = TextField(
              controller: _priceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'تكلفة الشراء (\$)', prefixIcon: Icon(Icons.attach_money, size: 18), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
            );
            final qtyField = TextField(
              controller: _qtyCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'الكمية', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
            );
            if (constraints.maxWidth < 400) {
              return Column(children: [priceField, const SizedBox(height: 8), qtyField]);
            }
            return Row(children: [Expanded(child: priceField), const SizedBox(width: 10), SizedBox(width: 80, child: qtyField)]);
          }),
          const SizedBox(height: 10),
          DropdownButtonFormField<String?>(
            value: _selectedSourceName,
            dropdownColor: AppTheme.darkSurface,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'الموقع',
              prefixIcon: Icon(Icons.language_outlined, size: 18),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('— بدون موقع —', style: TextStyle(color: Colors.white38))),
              ...sources.map((s) {
                final sName = s['name'] as String;
                final sRate = (s['rate_per_kg'] as num).toDouble();
                return DropdownMenuItem<String?>(
                  value: sName,
                  child: Text('$sName  (\$$sRate/kg)', style: const TextStyle(color: Colors.white)),
                );
              }),
            ],
            onChanged: (v) {
              final src = sources.firstWhere(
                (s) => s['name'] == v,
                orElse: () => <String, dynamic>{},
              );
              setState(() {
                _selectedSourceName = v;
                _currentShippingRate = v != null ? (src['rate_per_kg'] as num?)?.toDouble() ?? 0 : 0;
              });
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _weightCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'الوزن (كغ)',
              prefixIcon: const Icon(Icons.scale_outlined, size: 18),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              helperText: _currentShippingRate > 0
                  ? 'شحن محسوب: \$${calcShipping.toStringAsFixed(2)}  ($weight kg × \$$_currentShippingRate × $qty)'
                  : 'اختر الموقع لحساب تكلفة الشحن تلقائياً',
              helperStyle: TextStyle(color: _currentShippingRate > 0 ? AppTheme.secondary : Colors.white38, fontSize: 11),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _localPriceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'سعر البيع المحلي (د.ل)',
              prefixIcon: Icon(Icons.sell_outlined, size: 18),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
        ]),
      ),
    ]);
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
  final bool selected;
  final ValueChanged<bool?>? onToggle;
  const _OrderItemCard({
    required this.item,
    required this.statusColor,
    required this.translateStatus,
    this.onEdit,
    this.selected = false,
    this.onToggle,
  });

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
        border: Border.all(color: selected
            ? AppTheme.primary.withValues(alpha: 0.7)
            : isCancelled
              ? AppTheme.error.withValues(alpha: 0.4)
              : isSorted ? AppTheme.success.withValues(alpha: 0.5) : AppTheme.darkBorder),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Selection checkbox
        if (onToggle != null) ...[
          SizedBox(
            width: 24, height: 24,
            child: Checkbox(
              value: selected,
              onChanged: onToggle,
              activeColor: AppTheme.primary,
              side: BorderSide(color: Colors.white38, width: 1.5),
            ),
          ),
          const SizedBox(width: 10),
        ],
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
  late final TextEditingController _cartLinkCtrl;
  late final TextEditingController _totalCostUsdCtrl;
  late final TextEditingController _totalSalePriceLydCtrl;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _notesCtrl = TextEditingController(text: widget.order['notes'] as String? ?? '');
    _cartLinkCtrl = TextEditingController(text: widget.order['cart_link'] as String? ?? '');
    final costUsd = (widget.order['total_cost_usd'] as num?)?.toDouble();
    _totalCostUsdCtrl = TextEditingController(text: costUsd != null && costUsd > 0 ? costUsd.toString() : '');
    final saleLyd = (widget.order['total_sale_price_lyd'] as num?)?.toDouble();
    _totalSalePriceLydCtrl = TextEditingController(text: saleLyd != null && saleLyd > 0 ? saleLyd.toStringAsFixed(0) : '');
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _cartLinkCtrl.dispose();
    _totalCostUsdCtrl.dispose();
    _totalSalePriceLydCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: isMobile(context) ? 8 : 40, vertical: 24),
      backgroundColor: AppTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: dialogMaxWidth(context, desktopMax: 480), maxHeight: dialogMaxHeight(context)),
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
              controller: _cartLinkCtrl,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'رابط السلة',
                prefixIcon: Icon(Icons.shopping_cart_outlined),
                hintText: 'https://...',
                hintStyle: TextStyle(color: Colors.white24),
              ),
            ),
            const SizedBox(height: 14),
            if (widget.order['order_type'] == 'full_cart') ...[
              Row(children: [
                Expanded(child: TextField(
                  controller: _totalCostUsdCtrl,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'إجمالي التكلفة (\$)',
                    prefixIcon: Icon(Icons.attach_money, size: 18),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                )),
                const SizedBox(width: 12),
                Expanded(child: TextField(
                  controller: _totalSalePriceLydCtrl,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'إجمالي سعر البيع (د.ل)',
                    prefixIcon: Icon(Icons.sell_outlined, size: 18),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                )),
              ]),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => setState(() {
                    _totalCostUsdCtrl.clear();
                    _totalSalePriceLydCtrl.clear();
                  }),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('احسب من المنتجات'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.accent,
                    textStyle: const TextStyle(fontSize: 12),
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
              const Text(
                'اتركه فارغاً ليُحسب تلقائياً من المنتجات المضافة لهذه الطلبية',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
              const SizedBox(height: 14),
            ],
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
            const SizedBox(height: 24),
            SizedBox(height: 52, child: ElevatedButton.icon(
              onPressed: _saving ? null : () async {
                setState(() { _saving = true; _error = null; });
                final updates = <String, dynamic>{'version': widget.order['version']};
                updates['notes'] = _notesCtrl.text.trim();
                final link = _cartLinkCtrl.text.trim();
                if (link.isNotEmpty) updates['cart_link'] = link;
                if (widget.order['order_type'] == 'full_cart') {
                  final costText = _totalCostUsdCtrl.text.trim();
                  updates['total_cost_usd'] = costText.isEmpty
                      ? null
                      : double.tryParse(costText.replaceAll(',', '.'));
                  final saleText = _totalSalePriceLydCtrl.text.trim();
                  updates['total_sale_price_lyd'] = saleText.isEmpty
                      ? null
                      : double.tryParse(saleText.replaceAll(',', '.'));
                }
                try {
                  final nav = Navigator.of(context);
                  await widget.onSave(updates);
                  if (mounted) { nav.pop(); }
                } catch (e) {
                  if (mounted) {
                    setState(() {
                      _saving = false;
                      _error = e is DioException ? _dioMsg(e) : e.toString();
                    });
                  }
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
    double itemsCostUsd = 0;
    double shippingUsd = 0;
    double totalLocal = 0;
    double itemsCostUsdActual = 0;
    for (final raw in items) {
      final item = raw as Map<String, dynamic>;
      if ((item['status'] as String?) == 'cancelled') continue;
      final qty = (item['quantity'] as num?)?.toInt() ?? 1;
      final itemRate = (item['shipping_rate_per_kg'] as num?)?.toDouble() ?? 0;
      itemsCostUsd += ((item['unit_price_foreign'] as num?)?.toDouble() ?? 0) * qty;
      shippingUsd += ((item['weight'] as num?)?.toDouble() ?? 0) * itemRate * qty;
      totalLocal += ((item['unit_price_local'] as num?)?.toDouble() ?? (item['sale_price_lyd'] as num?)?.toDouble() ?? 0) * qty;
      itemsCostUsdActual += ((item['cost_usd'] as num?)?.toDouble() ?? 0) * qty;
    }

    final orderTotalCostUsd = (order['total_cost_usd'] as num?)?.toDouble();
    final orderTotalSaleLyd = (order['total_sale_price_lyd'] as num?)?.toDouble();
    final displayCostUsd = orderTotalCostUsd ?? (itemsCostUsdActual > 0 ? itemsCostUsdActual : null);
    final displaySaleLyd = orderTotalSaleLyd ?? (totalLocal > 0 ? totalLocal : null);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.calculate_outlined, color: AppTheme.accent, size: 18),
          const SizedBox(width: 8),
          const Text('الملخص المالي', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
        ]),
        const SizedBox(height: 12),
        _FinancialRow(label: 'تكلفة الشراء المبدئية (\$)', value: '\$${itemsCostUsd.toStringAsFixed(2)}'),
        const SizedBox(height: 6),
        if (shippingUsd > 0) ...[
          _FinancialRow(label: 'تكلفة الشحن (\$)', value: '\$${shippingUsd.toStringAsFixed(2)}'),
          const SizedBox(height: 6),
        ],
        if (displayCostUsd != null) ...[
          _FinancialRow(
            label: orderTotalCostUsd != null ? 'التكلفة الفعلية (يدوي) (\$)' : 'التكلفة الفعلية (من المنتجات) (\$)',
            value: '\$${displayCostUsd.toStringAsFixed(2)}',
            highlight: true,
          ),
          const SizedBox(height: 6),
        ],
        const Divider(height: 16, color: AppTheme.darkBorder),
        if (displaySaleLyd == null)
          const Center(
            child: Text('في انتظار تحديد سعر البيع', style: TextStyle(color: Colors.white38, fontSize: 13)),
          )
        else
          _FinancialRow(
            label: orderTotalSaleLyd != null ? 'سعر البيع (يدوي) (د.ل)' : 'سعر البيع (من المنتجات) (د.ل)',
            value: '${displaySaleLyd.toStringAsFixed(0)} د.ل',
            bold: true,
          ),
      ]),
    );
  }
}

class _FinancialRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final bool highlight;
  const _FinancialRow({required this.label, required this.value, this.bold = false, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
      Text(value, style: TextStyle(
        color: highlight ? AppTheme.accent : Colors.white70,
        fontWeight: bold || highlight ? FontWeight.w700 : FontWeight.w500,
        fontSize: bold ? 15 : 14,
      )),
    ]);
  }
}

// ─── Full Item Edit Dialog ────────────────────────────────

class _EditItemDialog extends ConsumerStatefulWidget {
  final String orderId;
  final Map<String, dynamic> order;
  final Map<String, dynamic> item;
  final Future<void> Function() onSaved;
  const _EditItemDialog({required this.orderId, required this.order, required this.item, required this.onSaved});

  @override
  ConsumerState<_EditItemDialog> createState() => _EditItemDialogState();
}

class _EditItemDialogState extends ConsumerState<_EditItemDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _skuCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _costUsdCtrl;
  late final TextEditingController _weightCtrl;
  late final TextEditingController _localPriceCtrl;
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _attr1Ctrl;
  late final TextEditingController _attr2Ctrl;
  String? _selectedCategory;
  late String _selectedStatus;
  String? _selectedSourceName;
  double _currentShippingRate = 0;
  bool _saving = false;
  String? _error;

  static const _categoryOptions = [
    ('clothing',    'ملابس'),
    ('electronics', 'إلكترونيات'),
    ('cosmetics',   'مستحضرات تجميل'),
    ('general',     'عام'),
  ];

  static const _legacyCategoryMap = {
    'Clothes':     'clothing',
    'Electronic':  'electronics',
    'Accessories': 'cosmetics',
    'Other':       'general',
  };

  String get _attr1Label {
    switch (_selectedCategory) {
      case 'clothing':    return 'المقاس';
      case 'electronics': return 'الإصدار';
      case 'cosmetics':   return 'التظليل';
      default:            return 'تفاصيل';
    }
  }

  String get _attr2Label {
    switch (_selectedCategory) {
      case 'clothing':    return 'اللون';
      case 'electronics': return 'السعة';
      case 'cosmetics':   return 'الحجم';
      default:            return '';
    }
  }

  bool get _showAttr1 => _selectedCategory != null;
  bool get _showAttr2 => _selectedCategory != null && _selectedCategory != 'general';

  Map<String, dynamic> _toAttributes() {
    final map = <String, dynamic>{};
    final v1 = _attr1Ctrl.text.trim();
    final v2 = _attr2Ctrl.text.trim();
    switch (_selectedCategory) {
      case 'clothing':    if (v1.isNotEmpty) map['size'] = v1; if (v2.isNotEmpty) map['color'] = v2;
      case 'electronics': if (v1.isNotEmpty) map['version'] = v1; if (v2.isNotEmpty) map['capacity'] = v2;
      case 'cosmetics':   if (v1.isNotEmpty) map['shade'] = v1; if (v2.isNotEmpty) map['volume'] = v2;
      case 'general':     if (v1.isNotEmpty) map['details'] = v1;
    }
    return map;
  }

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
    final costUsd = (widget.item['cost_usd'] as num?)?.toDouble() ?? 0;
    _costUsdCtrl = TextEditingController(text: costUsd > 0 ? costUsd.toString() : '');
    final weight = (widget.item['weight'] as num?)?.toDouble() ?? 0;
    _weightCtrl = TextEditingController(text: weight > 0 ? weight.toString() : '');
    final localPrice = (widget.item['unit_price_local'] as num?)?.toDouble() ?? 0;
    _localPriceCtrl = TextEditingController(text: localPrice > 0 ? localPrice.toStringAsFixed(0) : '');
    final qty  = (widget.item['quantity'] as num?)?.toInt() ?? 1;
    _qtyCtrl   = TextEditingController(text: qty.toString());
    // Category: prefer new lowercase key, fall back to legacy key with mapping
    final rawCat = (widget.item['category'] ?? widget.item['item_category']) as String?;
    _selectedCategory = rawCat != null
        ? (_categoryOptions.any((o) => o.$1 == rawCat)
            ? rawCat
            : _legacyCategoryMap[rawCat])
        : null;

    // Parse attributes JSON to pre-fill dynamic attribute fields
    String attr1 = '', attr2 = '';
    final rawAttrs = widget.item['attributes'];
    if (rawAttrs != null && rawAttrs.toString().isNotEmpty) {
      try {
        final attrs = (rawAttrs is String ? jsonDecode(rawAttrs) : rawAttrs) as Map<String, dynamic>;
        switch (_selectedCategory) {
          case 'clothing':    attr1 = attrs['size'] as String? ?? ''; attr2 = attrs['color'] as String? ?? '';
          case 'electronics': attr1 = attrs['version'] as String? ?? ''; attr2 = attrs['capacity'] as String? ?? '';
          case 'cosmetics':   attr1 = attrs['shade'] as String? ?? ''; attr2 = attrs['volume'] as String? ?? '';
          case 'general':     attr1 = attrs['details'] as String? ?? '';
        }
      } catch (_) {}
    }
    _attr1Ctrl = TextEditingController(text: attr1);
    _attr2Ctrl = TextEditingController(text: attr2);
    final rawStatus = (widget.item['status'] as String?) ?? 'pending';
    _selectedStatus = _statusOptions.any((o) => o.$1 == rawStatus) ? rawStatus : 'pending';
    _selectedSourceName = widget.item['source_name'] as String?;
    _currentShippingRate = (widget.item['shipping_rate_per_kg'] as num?)?.toDouble() ?? 0;
    _weightCtrl.addListener(() => setState(() {}));
    _qtyCtrl.addListener(() => setState(() {}));
    // Load sources if not already loaded
    Future.microtask(() => ref.read(shippingSourcesProvider.notifier).fetchSources());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _skuCtrl.dispose();
    _urlCtrl.dispose();
    _priceCtrl.dispose();
    _costUsdCtrl.dispose();
    _weightCtrl.dispose();
    _localPriceCtrl.dispose();
    _qtyCtrl.dispose();
    _attr1Ctrl.dispose();
    _attr2Ctrl.dispose();
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
          'product_name': name,
          'sku':          _skuCtrl.text.trim(),
          'product_url':  _urlCtrl.text.trim(),
          'unit_price_foreign': _parseDouble(_priceCtrl.text),
          if (_costUsdCtrl.text.trim().isNotEmpty)
            'cost_usd': _parseDouble(_costUsdCtrl.text),
          'weight':       _parseDouble(_weightCtrl.text),
          'shipping_rate_per_kg': _currentShippingRate,
          if (_selectedSourceName != null) 'source_name': _selectedSourceName,
          if (_localPriceCtrl.text.trim().isNotEmpty)
            'unit_price_local': _parseDouble(_localPriceCtrl.text),
          'quantity':     int.tryParse(_qtyCtrl.text.trim()) ?? 1,
          if (_selectedCategory != null) ...{
            'category':      _selectedCategory,
            'item_category': _selectedCategory,
            'attributes':    jsonEncode(_toAttributes()),
          },
          'status':       _selectedStatus,
          'version':      widget.item['version'],
        },
      );
      await widget.onSaved();
      if (mounted) { Navigator.of(context).pop(); }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e is DioException ? _dioMsg(e) : e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sourcesState = ref.watch(shippingSourcesProvider);
    final sources = sourcesState.valueOrNull ?? [];
    final isCancelled = _selectedStatus == 'cancelled';
    final weight = _parseDouble(_weightCtrl.text);
    final qty = int.tryParse(_qtyCtrl.text.trim()) ?? 1;
    final calcShipping = weight * _currentShippingRate * qty;

    final formContent = _buildEditItemFormContent(
      sources: sources,
      weight: weight,
      qty: qty,
      calcShipping: calcShipping,
      isCancelled: isCancelled,
    );
    final saveButton = SizedBox(height: 52, child: ElevatedButton.icon(
      onPressed: _saving ? null : _save,
      icon: _saving
        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
        : const Icon(Icons.save_rounded, size: 22),
      label: const Text('حفظ التغييرات', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
    ));

    if (isMobile(context)) {
      return Scaffold(
        backgroundColor: AppTheme.darkSurface,
        appBar: AppBar(
          backgroundColor: AppTheme.darkSurface,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white38),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Row(children: [
            Icon(Icons.edit_rounded, color: AppTheme.accent, size: 20),
            SizedBox(width: 8),
            Text('تعديل المنتج', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
          ]),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: formContent,
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: saveButton,
          ),
        ),
      );
    }

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      backgroundColor: AppTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: dialogMaxWidth(context, desktopMax: 480), maxHeight: dialogMaxHeight(context)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
            const SizedBox(height: 16),
            formContent,
            const SizedBox(height: 24),
            saveButton,
          ]),
        ),
      ),
    );
  }

  Widget _buildEditItemFormContent({
    required List<Map<String, dynamic>> sources,
    required double weight,
    required int qty,
    required double calcShipping,
    required bool isCancelled,
  }) {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_error != null) Container(
        padding: const EdgeInsets.all(10), margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(color: AppTheme.error.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
        child: Text(_error!, style: const TextStyle(color: AppTheme.error, fontSize: 13)),
      ),
      // Status dropdown
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        decoration: BoxDecoration(
          color: AppTheme.darkCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isCancelled ? AppTheme.error.withValues(alpha: 0.5) : AppTheme.darkBorder),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _selectedStatus, isExpanded: true,
            dropdownColor: AppTheme.darkCard,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            icon: const Icon(Icons.expand_more, color: Colors.white54),
            items: _statusOptions.map((opt) {
              final isCancel = opt.$1 == 'cancelled';
              return DropdownMenuItem(value: opt.$1,
                child: Text(opt.$2, style: TextStyle(color: isCancel ? AppTheme.error : Colors.white, fontWeight: isCancel ? FontWeight.w600 : FontWeight.normal)));
            }).toList(),
            onChanged: (v) { if (v != null) setState(() => _selectedStatus = v); },
          ),
        ),
      ),
      if (isCancelled) Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.error.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.error.withValues(alpha: 0.25)),
        ),
        child: const Row(children: [
          Icon(Icons.info_outline, color: AppTheme.error, size: 15), SizedBox(width: 8),
          Expanded(child: Text('هذا المنتج سيُستثنى من حساب التكلفة والتوصيل', style: TextStyle(color: AppTheme.error, fontSize: 12))),
        ]),
      ),
      const SizedBox(height: 16),
      // ── Section 1: تفاصيل المنتج ──────────────────────
      const Text('تفاصيل المنتج', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white60)),
      const Divider(color: AppTheme.darkBorder, height: 14),
      TextField(
        controller: _nameCtrl, style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(labelText: 'اسم المنتج *', prefixIcon: Icon(Icons.shopping_bag)),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _skuCtrl, style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(labelText: 'الرقم التسلسلي (الباركود)', prefixIcon: Icon(Icons.qr_code)),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _urlCtrl, style: const TextStyle(color: Colors.white), keyboardType: TextInputType.url,
        decoration: const InputDecoration(labelText: 'رابط المنتج', hintText: 'https://...', hintStyle: TextStyle(color: Colors.white24), prefixIcon: Icon(Icons.link)),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        decoration: BoxDecoration(color: AppTheme.darkCard, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.darkBorder)),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String?>(
            value: _selectedCategory, isExpanded: true, dropdownColor: AppTheme.darkCard,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            icon: const Icon(Icons.expand_more, color: Colors.white54),
            hint: const Text('الفئة (اختياري)', style: TextStyle(color: Colors.white38)),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('— بدون فئة —', style: TextStyle(color: Colors.white38))),
              ..._categoryOptions.map((opt) => DropdownMenuItem(value: opt.$1, child: Text(opt.$2, style: const TextStyle(color: Colors.white)))),
            ],
            onChanged: (v) => setState(() => _selectedCategory = v),
          ),
        ),
      ),
      if (_showAttr1) ...[
        const SizedBox(height: 12),
        if (_showAttr2)
          LayoutBuilder(builder: (context, constraints) {
            final attr1Field = TextField(controller: _attr1Ctrl, style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(labelText: _attr1Label, isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12)));
            final attr2Field = TextField(controller: _attr2Ctrl, style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(labelText: _attr2Label, isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12)));
            if (constraints.maxWidth < 400) {
              return Column(children: [attr1Field, const SizedBox(height: 8), attr2Field]);
            }
            return Row(children: [Expanded(child: attr1Field), const SizedBox(width: 12), Expanded(child: attr2Field)]);
          })
        else
          TextField(controller: _attr1Ctrl, style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(labelText: _attr1Label, isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12))),
      ],
      const SizedBox(height: 16),
      // ── Section 2: التفاصيل المالية ───────────────────
      const Text('التفاصيل المالية', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white60)),
      const Divider(color: AppTheme.darkBorder, height: 14),
      LayoutBuilder(builder: (context, constraints) {
        final priceField = TextField(
          controller: _priceCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(labelText: 'تكلفة الشراء (\$)', prefixIcon: Icon(Icons.attach_money, size: 18), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
        );
        final qtyField = TextField(
          controller: _qtyCtrl, keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(labelText: 'الكمية', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
        );
        if (constraints.maxWidth < 400) {
          return Column(children: [priceField, const SizedBox(height: 8), qtyField]);
        }
        return Row(children: [Expanded(child: priceField), const SizedBox(width: 10), SizedBox(width: 80, child: qtyField)]);
      }),
      const SizedBox(height: 12),
      TextField(
        controller: _costUsdCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(
          labelText: 'التكلفة الفعلية (\$)',
          hintText: 'بعد الشراء الفعلي',
          hintStyle: TextStyle(color: Colors.white24),
          prefixIcon: Icon(Icons.receipt_long_outlined, size: 18),
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        decoration: BoxDecoration(color: AppTheme.darkCard, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.darkBorder)),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String?>(
            value: _selectedSourceName,
            isExpanded: true, dropdownColor: AppTheme.darkCard,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            icon: const Icon(Icons.expand_more, color: Colors.white54),
            hint: const Text('الموقع (اختياري)', style: TextStyle(color: Colors.white38)),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('— بدون موقع —', style: TextStyle(color: Colors.white38))),
              ...sources.map((s) {
                final sName = s['name'] as String;
                final sRate = (s['rate_per_kg'] as num).toDouble();
                return DropdownMenuItem<String?>(
                  value: sName,
                  child: Text('$sName  (\$$sRate/kg)', style: const TextStyle(color: Colors.white)),
                );
              }),
            ],
            onChanged: (v) {
              final src = sources.firstWhere(
                (s) => s['name'] == v,
                orElse: () => <String, dynamic>{},
              );
              setState(() {
                _selectedSourceName = v;
                _currentShippingRate = v != null ? (src['rate_per_kg'] as num?)?.toDouble() ?? 0 : 0;
              });
            },
          ),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _weightCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: 'الوزن (كيلو)', prefixIcon: const Icon(Icons.scale_outlined, size: 18),
          isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          helperText: _currentShippingRate > 0
              ? 'شحن محسوب: \$${calcShipping.toStringAsFixed(2)}  ($weight kg × \$$_currentShippingRate × $qty)'
              : 'اختر الموقع لحساب تكلفة الشحن تلقائياً',
          helperStyle: TextStyle(color: _currentShippingRate > 0 ? AppTheme.secondary : Colors.white38, fontSize: 11),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _localPriceCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(labelText: 'سعر البيع المحلي (د.ل)', prefixIcon: Icon(Icons.sell_outlined, size: 18), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
      ),
    ]);
  }
}
