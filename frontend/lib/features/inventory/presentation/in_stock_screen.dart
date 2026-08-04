import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:estore_app/app/theme.dart';
import 'package:estore_app/core/providers.dart';
import 'package:estore_app/core/utils/dialog_utils.dart';

class InStockScreen extends ConsumerStatefulWidget {
  const InStockScreen({super.key});
  @override
  ConsumerState<InStockScreen> createState() => _InStockScreenState();
}

class _InStockScreenState extends ConsumerState<InStockScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(inStockProvider.notifier).fetchInStockItems());
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      ref.read(inStockProvider.notifier).fetchInStockItems(search: _searchCtrl.text.trim());
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    await ref.read(inStockProvider.notifier).loadMoreItems();
    if (mounted) setState(() => _loadingMore = false);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(inStockProvider);
    final notifier = ref.read(inStockProvider.notifier);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('البضاعة الفورية', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white)),
        const SizedBox(height: 4),
        const Text('منتجات جاهزة للبيع لزبائن جدد — تكاليفها صفر، ربحها كامل', style: TextStyle(color: Colors.white38, fontSize: 13)),
        const SizedBox(height: 16),
        // Search bar
        TextField(
          controller: _searchCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'بحث بالاسم أو رمز SKU...',
            hintStyle: const TextStyle(color: Colors.white38),
            prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 20),
            suffixIcon: _searchCtrl.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.white38, size: 18),
                  onPressed: () { _searchCtrl.clear(); },
                )
              : null,
            filled: true,
            fillColor: AppTheme.darkCard,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.darkBorder)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.darkBorder)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: state.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.cloud_off_rounded, color: AppTheme.error, size: 56),
              const SizedBox(height: 12),
              Text('$e', style: const TextStyle(color: Colors.white54), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => notifier.fetchInStockItems(search: _searchCtrl.text.trim()),
                child: const Text('إعادة المحاولة'),
              ),
            ])),
            data: (items) {
              if (items.isEmpty) {
                return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.inventory_2_outlined, color: Colors.white12, size: 72),
                  const SizedBox(height: 16),
                  Text(
                    _searchCtrl.text.isNotEmpty ? 'لا توجد نتائج' : 'لا توجد بضاعة فورية',
                    style: const TextStyle(color: Colors.white38, fontSize: 16),
                  ),
                  if (_searchCtrl.text.isEmpty) ...[
                    const SizedBox(height: 8),
                    const Text('عند إلغاء طلبية وتحويلها، ستظهر المنتجات هنا', style: TextStyle(color: Colors.white24, fontSize: 13), textAlign: TextAlign.center),
                  ],
                ]));
              }
              // Summary stats — only count items not yet written off
              double itemCost(Map<String, dynamic> it) {
                final costUsd = (it['cost_usd'] as num?)?.toDouble() ?? 0;
                final unitForeign = (it['unit_price_foreign'] as num?)?.toDouble() ?? 0;
                final weight = (it['weight'] as num?)?.toDouble() ?? 0;
                final rate = (it['shipping_rate_per_kg'] as num?)?.toDouble() ?? 0;
                final qty = (it['quantity'] as num?)?.toDouble() ?? 1;
                final perUnit = costUsd > 0 ? costUsd : unitForeign;
                return (perUnit + weight * rate) * qty;
              }
              final pendingItems = items.where((it) => it['written_off_settlement_id'] == null).toList();
              final totalSunkCost = pendingItems.fold<double>(0, (sum, it) => sum + itemCost(it));
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.warning.withValues(alpha: 0.2)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.warning_amber_rounded, color: AppTheme.warning, size: 20),
                    const SizedBox(width: 10),
                    Text('${pendingItems.length} منتج معلَّق · إجمالي التكاليف: \$${totalSunkCost.toStringAsFixed(2)}',
                      style: const TextStyle(color: AppTheme.warning, fontSize: 13, fontWeight: FontWeight.w600)),
                  ]),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () => notifier.fetchInStockItems(search: _searchCtrl.text.trim()),
                    child: ListView.separated(
                      itemCount: items.length + (notifier.hasMore ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (ctx, i) {
                        if (i == items.length) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Center(
                              child: _loadingMore
                                ? const CircularProgressIndicator()
                                : TextButton.icon(
                                    onPressed: _loadMore,
                                    icon: const Icon(Icons.expand_more_rounded),
                                    label: const Text('تحميل المزيد'),
                                    style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
                                  ),
                            ),
                          );
                        }
                        return _InStockItemCard(
                          item: items[i],
                          onRefresh: () => notifier.fetchInStockItems(search: _searchCtrl.text.trim()),
                        );
                      },
                    ),
                  ),
                ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}

// ─── In-Stock Item Card ────────────────────────────────────
class _InStockItemCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onRefresh;
  const _InStockItemCard({required this.item, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final name = item['product_name'] as String? ?? '—';
    final sku = item['sku'] as String? ?? '';
    final brand = item['brand'] as String? ?? '';
    final costUsd = (item['cost_usd'] as num?)?.toDouble() ?? 0;
    final unitForeign = (item['unit_price_foreign'] as num?)?.toDouble() ?? 0;
    final weight = (item['weight'] as num?)?.toDouble() ?? 0;
    final rate = (item['shipping_rate_per_kg'] as num?)?.toDouble() ?? 0;
    final qty = (item['quantity'] as num?)?.toDouble() ?? 1;
    final perUnit = costUsd > 0 ? costUsd : unitForeign;
    final sunkCost = (perUnit + weight * rate) * qty;
    final isWrittenOff = item['written_off_settlement_id'] != null;
    final imageUrl = item['product_thumb_url'] as String? ?? item['product_image_url'] as String?;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Thumbnail
          Container(
            width: 60, height: 60,
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(10),
            ),
            clipBehavior: Clip.antiAlias,
            child: imageUrl != null && imageUrl.isNotEmpty
              ? Image.network(imageUrl, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.inventory_2_outlined, color: Colors.white24, size: 28))
              : const Icon(Icons.inventory_2_outlined, color: Colors.white24, size: 28),
          ),
          const SizedBox(width: 14),
          // Info
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
            if (brand.isNotEmpty || sku.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text([if (brand.isNotEmpty) brand, if (sku.isNotEmpty) sku].join(' · '),
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ],
            const SizedBox(height: 8),
            if (isWrittenOff)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('احتُسبت كخسارة سابقاً', style: TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.w600)),
              )
            else
              Row(children: [
                const Icon(Icons.trending_down_rounded, color: AppTheme.error, size: 14),
                const SizedBox(width: 4),
                Text('خسارة مسجَّلة: \$${sunkCost.toStringAsFixed(2)}',
                  style: const TextStyle(color: AppTheme.error, fontSize: 12, fontWeight: FontWeight.w600)),
              ]),
          ])),
          // Action
          TextButton.icon(
            onPressed: () => _showReassignDialog(context),
            icon: const Icon(Icons.sell_outlined, size: 16),
            label: const Text('بيع لزبون جديد', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(foregroundColor: AppTheme.success),
          ),
        ]),
      ),
    );
  }

  void _showReassignDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _ReassignItemDialog(
        itemId: item['id'] as String,
        productName: item['product_name'] as String? ?? '—',
        onReassigned: onRefresh,
      ),
    );
  }
}

// ─── Reassign Dialog ───────────────────────────────────────
class _ReassignItemDialog extends ConsumerStatefulWidget {
  final String itemId;
  final String productName;
  final VoidCallback onReassigned;
  const _ReassignItemDialog({required this.itemId, required this.productName, required this.onReassigned});
  @override
  ConsumerState<_ReassignItemDialog> createState() => _ReassignItemDialogState();
}

class _ReassignItemDialogState extends ConsumerState<_ReassignItemDialog> {
  List<Map<String, dynamic>>? _orders;
  List<Map<String, dynamic>>? _filteredOrders;
  String? _selectedOrderId;
  final _priceCtrl = TextEditingController();
  final _orderSearchCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _loadingOrders = true;
  bool _submitting = false;
  bool _isNewCustomer = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOrders();
    _orderSearchCtrl.addListener(_filterOrders);
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _orderSearchCtrl.dispose();
    _phoneCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  void _filterOrders() {
    final q = _orderSearchCtrl.text.trim().toLowerCase();
    if (_orders == null) return;
    setState(() {
      _filteredOrders = q.isEmpty
        ? _orders
        : _orders!.where((o) {
            final customer = (o['customer_name'] as String? ?? '').toLowerCase();
            final id = (o['id'] as String? ?? '').toLowerCase();
            return customer.contains(q) || id.contains(q);
          }).toList();
      // Clear selection if not in filtered list
      if (_selectedOrderId != null &&
          !(_filteredOrders?.any((o) => o['id'] == _selectedOrderId) ?? false)) {
        _selectedOrderId = null;
      }
    });
  }

  Future<void> _loadOrders() async {
    try {
      final orders = await ref.read(inStockProvider.notifier).fetchActiveOrders();
      if (mounted) setState(() { _orders = orders; _filteredOrders = orders; _loadingOrders = false; });
    } catch (e) {
      if (mounted) setState(() { _loadingOrders = false; _error = '$e'; });
    }
  }

  Future<void> _submit() async {
    final price = double.tryParse(_priceCtrl.text.trim().replaceAll(',', '.'));
    if (price == null || price < 0) { setState(() => _error = 'أدخل سعر بيع صحيح'); return; }
    setState(() { _submitting = true; _error = null; });
    try {
      if (_isNewCustomer) {
        final phone = _phoneCtrl.text.trim();
        if (phone.isEmpty) { setState(() { _submitting = false; _error = 'أدخل رقم الهاتف'; }); return; }
        final notifier = ref.read(inStockProvider.notifier);
        final orderId = await notifier.reassignItemToNewCustomer(
          widget.itemId, phone, _nameCtrl.text.trim(), price,
        );
        widget.onReassigned();
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        final router = GoRouter.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(SnackBar(
          content: Text('تم البيع — ربح صافي: ${price.toStringAsFixed(2)} د.ل'),
          backgroundColor: AppTheme.success,
          action: SnackBarAction(
            label: 'عرض الطلبية',
            textColor: Colors.white,
            onPressed: () => router.push('/orders/$orderId'),
          ),
        ));
      } else {
        if (_selectedOrderId == null) { setState(() { _submitting = false; _error = 'اختر طلبية'; }); return; }
        await ref.read(inStockProvider.notifier).reassignItem(widget.itemId, _selectedOrderId!, price);
        widget.onReassigned();
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(SnackBar(
          content: Text('تم بيع المنتج — ربح صافي: ${price.toStringAsFixed(2)} د.ل'),
          backgroundColor: AppTheme.success,
        ));
      }
    } catch (e) {
      if (mounted) setState(() { _submitting = false; _error = '$e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: isMobile(context) ? 8 : 40, vertical: 24),
      backgroundColor: AppTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: dialogMaxWidth(context, desktopMax: 440), maxHeight: dialogMaxHeight(context, cap: 620)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Icon(Icons.sell_outlined, color: AppTheme.success, size: 22),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('بيع لزبون', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                Text(widget.productName, style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ])),
              IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.of(context).pop()),
            ]),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppTheme.success.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
              child: const Text(
                'تكاليف الشراء ستُصفَّر تلقائياً — سعر البيع = 100% ربح صافي',
                style: TextStyle(color: AppTheme.success, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            // Mode toggle
            Row(children: [
              Expanded(child: GestureDetector(
                onTap: () => setState(() { _isNewCustomer = false; }),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: !_isNewCustomer ? AppTheme.primary.withValues(alpha: 0.15) : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: !_isNewCustomer ? AppTheme.primary : AppTheme.darkBorder),
                  ),
                  child: Text('طلبية موجودة', textAlign: TextAlign.center,
                    style: TextStyle(color: !_isNewCustomer ? AppTheme.primary : Colors.white54, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              )),
              const SizedBox(width: 8),
              Expanded(child: GestureDetector(
                onTap: () => setState(() { _isNewCustomer = true; }),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: _isNewCustomer ? AppTheme.success.withValues(alpha: 0.15) : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _isNewCustomer ? AppTheme.success : AppTheme.darkBorder),
                  ),
                  child: Text('زبون جديد', textAlign: TextAlign.center,
                    style: TextStyle(color: _isNewCustomer ? AppTheme.success : Colors.white54, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              )),
            ]),
            const SizedBox(height: 16),
            if (_error != null) Container(
              padding: const EdgeInsets.all(10), margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: AppTheme.error.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
              child: Text(_error!, style: const TextStyle(color: AppTheme.error, fontSize: 13)),
            ),
            // Existing order mode
            if (!_isNewCustomer) ...[
              if (_loadingOrders)
                const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 12), child: CircularProgressIndicator()))
              else if (_orders != null) ...[
                TextField(
                  controller: _orderSearchCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: 'بحث في الطلبيات...',
                    hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                    prefixIcon: Icon(Icons.search, color: Colors.white38, size: 18),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _selectedOrderId,
                  dropdownColor: AppTheme.darkCard,
                  decoration: InputDecoration(
                    filled: true, fillColor: AppTheme.darkCard,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.darkBorder)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.darkBorder)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  hint: const Text('— اختر طلبية —', style: TextStyle(color: Colors.white38, fontSize: 13)),
                  items: (_filteredOrders ?? []).map((o) {
                    final id = o['id'] as String;
                    final shortId = id.length > 8 ? id.substring(0, 8) : id;
                    final customer = o['customer_name'] as String? ?? '—';
                    return DropdownMenuItem(
                      value: id,
                      child: Text('طلبية #$shortId — $customer',
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _selectedOrderId = v),
                ),
              ],
            ],
            // New customer mode
            if (_isNewCustomer) ...[
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'رقم الهاتف *',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _nameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'الاسم (اختياري)',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _priceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'سعر البيع الجديد (د.ل)',
                prefixIcon: Icon(Icons.sell_outlined),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(height: 48, child: ElevatedButton(
              onPressed: (_submitting || _loadingOrders) ? null : _submit,
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
              child: _submitting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('تأكيد البيع — ربح صافي 100%', style: TextStyle(fontWeight: FontWeight.w700)),
            )),
          ]),
        ),
      ),
    );
  }
}
