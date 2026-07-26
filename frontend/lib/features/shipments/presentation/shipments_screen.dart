import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:estore_app/app/theme.dart';
import 'package:estore_app/core/providers.dart';
import 'package:uuid/uuid.dart';

class ShipmentsScreen extends ConsumerStatefulWidget {
  const ShipmentsScreen({super.key});

  @override
  ConsumerState<ShipmentsScreen> createState() => _ShipmentsScreenState();
}

class _ShipmentsScreenState extends ConsumerState<ShipmentsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(shipmentsProvider.notifier).fetchShipments());
  }

  void _showNewShipmentDialog() {
    showDialog(context: context, builder: (_) => _NewShipmentDialog(
      onCreated: () => ref.read(shipmentsProvider.notifier).fetchShipments(),
    ));
  }

  void _showMasterShipmentDialog() {
    showDialog(context: context, builder: (_) => _MasterShipmentDialog(
      onCreated: () => ref.read(shipmentsProvider.notifier).fetchShipments(),
    ));
  }

  void _showShipmentDetail(Map<String, dynamic> shipment) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.darkSurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      builder: (_) => _ShipmentDetailSheet(shipment: shipment),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(shipmentsProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('Shipments', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white)),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: _showNewShipmentDialog,
              icon: const Icon(Icons.add, size: 20),
              label: const Text('شحنة جديدة'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _showMasterShipmentDialog,
              icon: const Icon(Icons.inventory, size: 20),
              label: const Text('شحنة رئيسية'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.secondary,
                side: const BorderSide(color: AppTheme.secondary),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
            ),
          ]),
          const SizedBox(height: 24),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.darkSurface, borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.darkBorder),
              ),
              child: state.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: AppTheme.error, size: 48),
                    const SizedBox(height: 12),
                    const Text('Failed to load shipments', style: TextStyle(color: Colors.white70)),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () => ref.read(shipmentsProvider.notifier).fetchShipments(),
                      child: const Text('Retry'),
                    ),
                  ],
                )),
                data: (shipments) => shipments.isEmpty
                    ? const Center(child: Text('No shipments found', style: TextStyle(color: Colors.white38)))
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: shipments.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.darkBorder),
                        itemBuilder: (context, index) {
                          final s = shipments[index];
                          final status = (s['status'] ?? 'pending') as String;
                          final color = _statusColor(status);
                          final isMaster = s['is_master'] == true || s['type'] == 'master';
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                            onTap: () => _showShipmentDetail(s),
                            leading: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                isMaster ? Icons.inventory_2 : Icons.local_shipping,
                                color: color, size: 22,
                              ),
                            ),
                            title: Text(s['tracking_number'] ?? s['name'] ?? s['id'] ?? '',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                            subtitle: Text('${s['carrier'] ?? s['supplier'] ?? 'Unknown'} • ${s['items_count'] ?? '?'} items',
                              style: const TextStyle(color: Colors.white54, fontSize: 13)),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(_translateStatus(status),
                                  style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.chevron_right, color: Colors.white38),
                            ]),
                          );
                        },
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _translateStatus(String status) {
    switch (status) {
      case 'pending': return 'قيد الانتظار';
      case 'in_transit': return 'في الطريق';
      case 'arrived': return 'وصلت';
      case 'processing': return 'قيد المعالجة';
      case 'delivered': return 'تم التوصيل';
      case 'customs': return 'في الجمارك';
      default: return status.replaceAll('_', ' ');
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pending': return AppTheme.accent;
      case 'in_transit': return AppTheme.secondary;
      case 'arrived': case 'delivered': return AppTheme.success;
      case 'processing': return AppTheme.warning;
      case 'customs': return AppTheme.primary;
      default: return AppTheme.primary;
    }
  }
}

// ─── New Shipment Dialog ───────────────────────────────────────
class _NewShipmentDialog extends ConsumerStatefulWidget {
  final VoidCallback onCreated;
  const _NewShipmentDialog({required this.onCreated});
  @override
  ConsumerState<_NewShipmentDialog> createState() => _NewShipmentDialogState();
}

class _NewShipmentDialogState extends ConsumerState<_NewShipmentDialog> {
  final _trackingCtrl = TextEditingController();
  final _supplierCtrl = TextEditingController();
  DateTime? _shipDate;
  bool _loading = false;
  String? _error;

  @override
  void dispose() { _trackingCtrl.dispose(); _supplierCtrl.dispose(); super.dispose(); }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: AppTheme.primary, surface: AppTheme.darkSurface)),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _shipDate = picked);
  }

  Future<void> _create() async {
    if (_trackingCtrl.text.trim().isEmpty) { setState(() => _error = 'Tracking number is required'); return; }
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(shipmentsProvider.notifier).createShipment({
        'id': const Uuid().v4(),
        'tracking_number': _trackingCtrl.text.trim(),
        'supplier': _supplierCtrl.text.trim(),
        if (_shipDate != null) 'ship_date': _shipDate!.toIso8601String().split('T')[0],
      });
      widget.onCreated();
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ تم إنشاء الشحنة'), backgroundColor: AppTheme.success));
      }
    } catch (e) { setState(() => _error = e.toString()); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 450),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.local_shipping, color: AppTheme.primary, size: 22),
              ),
              const SizedBox(width: 12),
              const Text('شحنة جديدة', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white)),
            ]),
            const SizedBox(height: 24),
            if (_error != null) Container(
              padding: const EdgeInsets.all(10), margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: AppTheme.error.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
              child: Text(_error!, style: const TextStyle(color: AppTheme.error, fontSize: 13)),
            ),
            TextField(controller: _trackingCtrl, style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'رقم التتبع *', prefixIcon: Icon(Icons.qr_code))),
            const SizedBox(height: 12),
            TextField(controller: _supplierCtrl, style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'المورد', prefixIcon: Icon(Icons.store))),
            const SizedBox(height: 12),
            // Date picker
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: AppTheme.darkCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.darkBorder),
                ),
                child: Row(children: [
                  const Icon(Icons.calendar_today, color: Colors.white54, size: 20),
                  const SizedBox(width: 12),
                  Text(
                    _shipDate != null ? '${_shipDate!.year}-${_shipDate!.month.toString().padLeft(2, '0')}-${_shipDate!.day.toString().padLeft(2, '0')}' : 'تاريخ الشحن (اختياري)',
                    style: TextStyle(color: _shipDate != null ? Colors.white : Colors.white38, fontSize: 14),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(height: 52, child: ElevatedButton.icon(
              onPressed: _loading ? null : _create,
              icon: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.add, size: 22),
              label: Text(_loading ? 'جاري الإنشاء...' : 'إنشاء شحنة', style: const TextStyle(fontSize: 15)),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            )),
          ]),
        ),
      ),
    );
  }
}

// ─── Master Shipment Dialog ─────────────────────────────────────
class _MasterShipmentDialog extends ConsumerStatefulWidget {
  final VoidCallback onCreated;
  const _MasterShipmentDialog({required this.onCreated});
  @override
  ConsumerState<_MasterShipmentDialog> createState() => _MasterShipmentDialogState();
}

class _MasterShipmentDialogState extends ConsumerState<_MasterShipmentDialog> {
  final _nameCtrl = TextEditingController();
  final _customsCostCtrl = TextEditingController();
  final _freightCostCtrl = TextEditingController();
  final _otherCostsCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() { _nameCtrl.dispose(); _customsCostCtrl.dispose(); _freightCostCtrl.dispose(); _otherCostsCtrl.dispose(); super.dispose(); }

  Future<void> _create() async {
    if (_nameCtrl.text.trim().isEmpty) { setState(() => _error = 'Name is required'); return; }
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(shipmentsProvider.notifier).createMasterShipment({
        'id': const Uuid().v4(),
        'name': _nameCtrl.text.trim(),
        if (_customsCostCtrl.text.isNotEmpty) 'customs_cost': double.tryParse(_customsCostCtrl.text) ?? 0,
        if (_freightCostCtrl.text.isNotEmpty) 'freight_cost': double.tryParse(_freightCostCtrl.text) ?? 0,
        if (_otherCostsCtrl.text.isNotEmpty) 'other_costs': double.tryParse(_otherCostsCtrl.text) ?? 0,
      });
      widget.onCreated();
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ تم إنشاء الشحنة الرئيسية'), backgroundColor: AppTheme.success));
      }
    } catch (e) { setState(() => _error = e.toString()); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 450),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppTheme.secondary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.inventory_2, color: AppTheme.secondary, size: 22),
              ),
              const SizedBox(width: 12),
              const Text('شحنة رئيسية', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white)),
            ]),
            const SizedBox(height: 24),
            if (_error != null) Container(
              padding: const EdgeInsets.all(10), margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: AppTheme.error.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
              child: Text(_error!, style: const TextStyle(color: AppTheme.error, fontSize: 13)),
            ),
            TextField(controller: _nameCtrl, style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'اسم الشحنة *', hintText: 'مثال: شحنة جوية يوليو 2026', hintStyle: TextStyle(color: Colors.white24), prefixIcon: Icon(Icons.label))),
            const SizedBox(height: 12),
            TextField(controller: _customsCostCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'تكلفة الجمارك', prefixIcon: Icon(Icons.account_balance))),
            const SizedBox(height: 12),
            TextField(controller: _freightCostCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'تكلفة الشحن', prefixIcon: Icon(Icons.flight))),
            const SizedBox(height: 12),
            TextField(controller: _otherCostsCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'تكاليف أخرى', prefixIcon: Icon(Icons.more_horiz))),
            const SizedBox(height: 24),
            SizedBox(height: 52, child: ElevatedButton.icon(
              onPressed: _loading ? null : _create,
              icon: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.add, size: 22),
              label: Text(_loading ? 'جاري الإنشاء...' : 'إنشاء شحنة رئيسية', style: const TextStyle(fontSize: 15)),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.secondary),
            )),
          ]),
        ),
      ),
    );
  }
}

// ─── Shipment Detail Bottom Sheet ─────────────────────────────
class _ShipmentDetailSheet extends StatelessWidget {
  final Map<String, dynamic> shipment;
  const _ShipmentDetailSheet({required this.shipment});

  Color _statusColor(String status) {
    switch (status) {
      case 'pending': return AppTheme.accent;
      case 'in_transit': return AppTheme.secondary;
      case 'arrived': case 'delivered': return AppTheme.success;
      case 'processing': return AppTheme.warning;
      case 'customs': return AppTheme.primary;
      default: return AppTheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = (shipment['status'] ?? 'pending') as String;
    final color = _statusColor(status);
    final tracking = shipment['tracking_number'] ?? shipment['name'] ?? shipment['id'] ?? '';
    final carrier = shipment['carrier'] ?? shipment['supplier'] ?? 'Unknown';
    final items = shipment['items'] as List<dynamic>? ?? [];
    final isMaster = shipment['is_master'] == true || shipment['type'] == 'master';

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.3,
      expand: false,
      builder: (_, scrollCtrl) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Handle
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),
          // Header
          Row(children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14)),
              child: Icon(isMaster ? Icons.inventory_2 : Icons.local_shipping, color: color, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tracking as String, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(carrier as String, style: const TextStyle(color: Colors.white54, fontSize: 14)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
              child: Text(status.replaceAll('_', ' '), style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 20),
          // Costs (if master)
          if (isMaster) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppTheme.darkCard, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                _costItem('Customs', shipment['customs_cost']),
                _costItem('Freight', shipment['freight_cost']),
                _costItem('Other', shipment['other_costs']),
              ]),
            ),
            const SizedBox(height: 16),
          ],
          // Items
          Text('Items (${items.length})', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Expanded(
            child: items.isEmpty
              ? const Center(child: Text('No items linked', style: TextStyle(color: Colors.white38)))
              : ListView.separated(
                  controller: scrollCtrl,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (ctx, i) {
                    final item = items[i] as Map<String, dynamic>;
                    return Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: AppTheme.darkCard.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(10)),
                      child: Row(children: [
                        const Icon(Icons.shopping_bag_outlined, color: Colors.white38, size: 18),
                        const SizedBox(width: 10),
                        Expanded(child: Text(item['product_name'] ?? 'Unknown', style: const TextStyle(color: Colors.white, fontSize: 13))),
                        Text(item['customer_name'] ?? '', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      ]),
                    );
                  },
                ),
          ),
        ]),
      ),
    );
  }

  Widget _costItem(String label, dynamic value) {
    return Expanded(child: Column(children: [
      Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
      const SizedBox(height: 4),
      Text(value != null ? '\$${(value as num).toStringAsFixed(2)}' : '—', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
    ]));
  }
}
