import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:estore_app/app/theme.dart';
import 'package:estore_app/core/providers.dart';

class InStockScreen extends ConsumerStatefulWidget {
  const InStockScreen({super.key});
  @override
  ConsumerState<InStockScreen> createState() => _InStockScreenState();
}

class _InStockScreenState extends ConsumerState<InStockScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(inStockProvider.notifier).fetchInStockItems());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(inStockProvider);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('البضاعة الفورية', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white)),
        const SizedBox(height: 4),
        const Text('منتجات جاهزة للبيع لزبائن جدد — تكاليفها صفر، ربحها كامل', style: TextStyle(color: Colors.white38, fontSize: 13)),
        const SizedBox(height: 20),
        Expanded(
          child: state.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.cloud_off_rounded, color: AppTheme.error, size: 56),
              const SizedBox(height: 12),
              Text('$e', style: const TextStyle(color: Colors.white54), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.read(inStockProvider.notifier).fetchInStockItems(),
                child: const Text('إعادة المحاولة'),
              ),
            ])),
            data: (items) {
              if (items.isEmpty) {
                return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.inventory_2_outlined, color: Colors.white12, size: 72),
                  const SizedBox(height: 16),
                  const Text('لا توجد بضاعة فورية', style: TextStyle(color: Colors.white38, fontSize: 16)),
                  const SizedBox(height: 8),
                  const Text('عند إلغاء طلبية وتحويلها، ستظهر المنتجات هنا', style: TextStyle(color: Colors.white24, fontSize: 13), textAlign: TextAlign.center),
                ]));
              }
              // Summary stats
              final totalSunkCost = items.fold<double>(0, (sum, it) {
                final p = (it['purchase_price'] as num?)?.toDouble() ?? 0;
                final s = (it['shipping_cost_foreign'] as num?)?.toDouble() ?? 0;
                return sum + p + s;
              });
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
                    Text('${items.length} منتج · إجمالي التكاليف المسجَّلة كخسارة: \$${totalSunkCost.toStringAsFixed(2)}',
                      style: const TextStyle(color: AppTheme.warning, fontSize: 13, fontWeight: FontWeight.w600)),
                  ]),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () => ref.read(inStockProvider.notifier).fetchInStockItems(),
                    child: ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (ctx, i) => _InStockItemCard(
                        item: items[i],
                        onRefresh: () => ref.read(inStockProvider.notifier).fetchInStockItems(),
                      ),
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
    final purchase = (item['purchase_price'] as num?)?.toDouble() ?? 0;
    final shipping = (item['shipping_cost_foreign'] as num?)?.toDouble() ?? 0;
    final sunkCost = purchase + shipping;
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
  String? _selectedOrderId;
  final _priceCtrl = TextEditingController();
  bool _loadingOrders = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() { super.initState(); _loadOrders(); }

  @override
  void dispose() { _priceCtrl.dispose(); super.dispose(); }

  Future<void> _loadOrders() async {
    try {
      final orders = await ref.read(inStockProvider.notifier).fetchActiveOrders();
      if (mounted) setState(() { _orders = orders; _loadingOrders = false; });
    } catch (e) {
      if (mounted) setState(() { _loadingOrders = false; _error = '$e'; });
    }
  }

  Future<void> _submit() async {
    final price = double.tryParse(_priceCtrl.text.trim());
    if (_selectedOrderId == null) { setState(() => _error = 'اختر طلبية'); return; }
    if (price == null || price < 0) { setState(() => _error = 'أدخل سعر بيع صحيح'); return; }
    setState(() { _submitting = true; _error = null; });
    try {
      await ref.read(inStockProvider.notifier).reassignItem(widget.itemId, _selectedOrderId!, price);
      widget.onReassigned();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(
        content: Text('تم بيع المنتج — ربح صافي: \$${price.toStringAsFixed(2)}'),
        backgroundColor: AppTheme.success,
      ));
    } catch (e) {
      if (mounted) setState(() { _submitting = false; _error = '$e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Icon(Icons.sell_outlined, color: AppTheme.success, size: 22),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('بيع لزبون جديد', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
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
            const SizedBox(height: 20),
            if (_error != null) Container(
              padding: const EdgeInsets.all(10), margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: AppTheme.error.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
              child: Text(_error!, style: const TextStyle(color: AppTheme.error, fontSize: 13)),
            ),
            if (_loadingOrders)
              const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 12), child: CircularProgressIndicator()))
            else if (_orders != null) ...[
              const Text('اختر طلبية', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600)),
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
                items: _orders!.map((o) {
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
            const SizedBox(height: 16),
            TextField(
              controller: _priceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'سعر البيع الجديد (\$)',
                prefixIcon: Icon(Icons.attach_money_rounded),
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
