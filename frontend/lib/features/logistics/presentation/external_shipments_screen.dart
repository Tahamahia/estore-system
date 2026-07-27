import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:estore_app/app/theme.dart';
import 'package:estore_app/core/providers.dart';

class ExternalShipmentsScreen extends ConsumerStatefulWidget {
  const ExternalShipmentsScreen({super.key});
  @override
  ConsumerState<ExternalShipmentsScreen> createState() => _ExternalShipmentsScreenState();
}

class _ExternalShipmentsScreenState extends ConsumerState<ExternalShipmentsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(externalShipmentsProvider.notifier).fetchShipments());
  }

  void _showCreate() {
    showDialog(
      context: context,
      builder: (_) => _CreateExternalShipmentDialog(
        onCreated: () => ref.read(externalShipmentsProvider.notifier).fetchShipments(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(externalShipmentsProvider);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('الشحنات الخارجية', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white)),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: _showCreate,
            icon: const Icon(Icons.add, size: 20),
            label: const Text('شحنة جديدة'),
          ),
        ]),
        const SizedBox(height: 8),
        const Text('تتبع الطرود القادمة من الموردين الخارجيين', style: TextStyle(color: Colors.white38, fontSize: 13)),
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
                onPressed: () => ref.read(externalShipmentsProvider.notifier).fetchShipments(),
                child: const Text('إعادة المحاولة'),
              ),
            ])),
            data: (shipments) {
              if (shipments.isEmpty) {
                return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.flight_land_rounded, color: Colors.white12, size: 72),
                  const SizedBox(height: 16),
                  const Text('لا توجد شحنات خارجية', style: TextStyle(color: Colors.white38, fontSize: 16)),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _showCreate,
                    icon: const Icon(Icons.add, size: 20),
                    label: const Text('إضافة أول شحنة'),
                  ),
                ]));
              }
              return RefreshIndicator(
                onRefresh: () => ref.read(externalShipmentsProvider.notifier).fetchShipments(),
                child: ListView.separated(
                  itemCount: shipments.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (ctx, i) => _ExternalShipmentCard(
                    shipment: shipments[i],
                    onRefresh: () => ref.read(externalShipmentsProvider.notifier).fetchShipments(),
                  ),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ─── Shipment Card ─────────────────────────────────────────
class _ExternalShipmentCard extends StatefulWidget {
  final Map<String, dynamic> shipment;
  final VoidCallback onRefresh;
  const _ExternalShipmentCard({required this.shipment, required this.onRefresh});
  @override
  State<_ExternalShipmentCard> createState() => _ExternalShipmentCardState();
}

class _ExternalShipmentCardState extends State<_ExternalShipmentCard> {
  bool _syncing = false;

  Color _manualStatusColor(String status) {
    switch (status) {
      case 'arrived_at_warehouse': return AppTheme.success;
      case 'at_local_forwarder': return AppTheme.warning;
      default: return AppTheme.accent;
    }
  }

  String _manualStatusLabel(String status) {
    switch (status) {
      case 'in_transit': return 'في الطريق';
      case 'at_local_forwarder': return 'عند الوكيل المحلي';
      case 'arrived_at_warehouse': return 'وصلت المستودع';
      default: return status;
    }
  }

  Future<void> _sync(BuildContext context) async {
    final notifier = ProviderScope.containerOf(context).read(externalShipmentsProvider.notifier);
    setState(() => _syncing = true);
    try {
      final result = await notifier.syncTracking(widget.shipment['id'] as String);
      if (!context.mounted) return;
      final tracking = result['tracking'] as Map<String, dynamic>? ?? {};
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${tracking['courier'] ?? ''} — ${tracking['lastEvent'] ?? ''}'),
        backgroundColor: AppTheme.success,
      ));
      widget.onRefresh();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$e'),
        backgroundColor: AppTheme.error,
      ));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  void _showDetail(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _ShipmentDetailDialog(
        shipmentId: widget.shipment['id'] as String,
        onRefresh: widget.onRefresh,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.shipment;
    final tracking = s['tracking_number'] as String? ?? '—';
    final courier = s['courier_code'] as String? ?? '';
    final apiStatus = s['api_status'] as String? ?? 'unknown';
    final manualStatus = s['manual_status'] as String? ?? 'in_transit';
    final itemCount = (s['item_count'] as num?)?.toInt() ?? 0;
    final statusColor = _manualStatusColor(manualStatus);

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: Column(children: [
        // Header row
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.flight_land_rounded, color: AppTheme.primary, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tracking, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15, fontFamily: 'monospace')),
              if (courier.isNotEmpty)
                Text(courier, style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ])),
            // API status chip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(apiStatus, style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ),
            const SizedBox(width: 8),
            // Manual status badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: statusColor.withValues(alpha: 0.4)),
              ),
              child: Text(_manualStatusLabel(manualStatus), style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
        // Footer row
        Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: AppTheme.darkBorder)),
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
          ),
          child: Row(children: [
            const SizedBox(width: 16),
            Icon(Icons.inventory_2_outlined, color: Colors.white38, size: 16),
            const SizedBox(width: 6),
            Text('$itemCount منتج', style: const TextStyle(color: Colors.white54, fontSize: 13)),
            const Spacer(),
            // Sync button
            TextButton.icon(
              onPressed: _syncing ? null : () => _sync(context),
              icon: _syncing
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.radar_rounded, size: 16),
              label: const Text('تتبع', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(foregroundColor: AppTheme.accent),
            ),
            // Detail button
            TextButton.icon(
              onPressed: () => _showDetail(context),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('التفاصيل', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
            ),
            const SizedBox(width: 8),
          ]),
        ),
      ]),
    );
  }
}

// ─── Create Dialog ─────────────────────────────────────────
class _CreateExternalShipmentDialog extends ConsumerStatefulWidget {
  final VoidCallback onCreated;
  const _CreateExternalShipmentDialog({required this.onCreated});
  @override
  ConsumerState<_CreateExternalShipmentDialog> createState() => _CreateExternalShipmentDialogState();
}

class _CreateExternalShipmentDialogState extends ConsumerState<_CreateExternalShipmentDialog> {
  final _trackingCtrl = TextEditingController();
  final _courierCtrl  = TextEditingController();
  final _notesCtrl    = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() { _trackingCtrl.dispose(); _courierCtrl.dispose(); _notesCtrl.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (_trackingCtrl.text.trim().isEmpty) { setState(() => _error = 'رقم التتبع مطلوب'); return; }
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(externalShipmentsProvider.notifier).createShipment({
        'id': const Uuid().v4(),
        'tracking_number': _trackingCtrl.text.trim(),
        if (_courierCtrl.text.trim().isNotEmpty) 'courier_code': _courierCtrl.text.trim(),
        if (_notesCtrl.text.trim().isNotEmpty) 'notes': _notesCtrl.text.trim(),
      });
      widget.onCreated();
      if (mounted) Navigator.of(context).pop();
    } catch (e) { setState(() => _error = '$e'); }
    finally { if (mounted) setState(() => _loading = false); }
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
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.flight_land_rounded, color: AppTheme.primary, size: 22),
              ),
              const SizedBox(width: 12),
              const Text('شحنة خارجية جديدة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
            ]),
            const SizedBox(height: 24),
            if (_error != null) Container(
              padding: const EdgeInsets.all(10), margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: AppTheme.error.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
              child: Text(_error!, style: const TextStyle(color: AppTheme.error, fontSize: 13)),
            ),
            TextField(
              controller: _trackingCtrl,
              style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
              decoration: const InputDecoration(labelText: 'رقم التتبع *', prefixIcon: Icon(Icons.qr_code_rounded)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _courierCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'اسم شركة الشحن (اختياري)', prefixIcon: Icon(Icons.local_shipping_outlined)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesCtrl,
              style: const TextStyle(color: Colors.white),
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'ملاحظات', prefixIcon: Icon(Icons.notes_rounded)),
            ),
            const SizedBox(height: 24),
            SizedBox(height: 48, child: ElevatedButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('إنشاء الشحنة'),
            )),
          ]),
        ),
      ),
    );
  }
}

// ─── Shipment Detail Dialog ─────────────────────────────────
class _ShipmentDetailDialog extends ConsumerStatefulWidget {
  final String shipmentId;
  final VoidCallback onRefresh;
  const _ShipmentDetailDialog({required this.shipmentId, required this.onRefresh});
  @override
  ConsumerState<_ShipmentDetailDialog> createState() => _ShipmentDetailDialogState();
}

class _ShipmentDetailDialogState extends ConsumerState<_ShipmentDetailDialog> {
  Map<String, dynamic>? _shipment;
  bool _loading = true;
  String? _error;
  bool _updatingStatus = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await ref.read(externalShipmentsProvider.notifier).getShipment(widget.shipmentId);
      if (mounted) setState(() { _shipment = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = '$e'; });
    }
  }

  Future<void> _updateManualStatus(String newStatus) async {
    setState(() => _updatingStatus = true);
    try {
      await ref.read(externalShipmentsProvider.notifier).updateShipment(
        widget.shipmentId,
        {'manual_status': newStatus},
      );
      widget.onRefresh();
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppTheme.error));
    } finally {
      if (mounted) setState(() => _updatingStatus = false);
    }
  }

  void _showAttachItems() {
    Navigator.of(context).pop();
    showDialog(
      context: context,
      builder: (_) => _AttachItemsDialog(
        shipmentId: widget.shipmentId,
        onAttached: widget.onRefresh,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: AppTheme.error)))
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  // Header
                  Row(children: [
                    const Icon(Icons.flight_land_rounded, color: AppTheme.primary, size: 22),
                    const SizedBox(width: 10),
                    Expanded(child: Text(
                      _shipment!['tracking_number'] as String? ?? '—',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16, fontFamily: 'monospace'),
                    )),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white54),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  if (_shipment!['courier_code'] != null)
                    Text(_shipment!['courier_code'] as String, style: const TextStyle(color: Colors.white54, fontSize: 13)),
                  const SizedBox(height: 16),

                  // Manual status selector
                  const Text('الحالة اليدوية', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(children: [
                    for (final entry in const {
                      'in_transit': 'في الطريق',
                      'at_local_forwarder': 'عند الوكيل',
                      'arrived_at_warehouse': 'وصلت',
                    }.entries) ...[
                      _StatusChip(
                        label: entry.value,
                        isActive: (_shipment!['manual_status'] as String?) == entry.key,
                        activeColor: entry.key == 'arrived_at_warehouse' ? AppTheme.success : AppTheme.warning,
                        onTap: _updatingStatus ? null : () => _updateManualStatus(entry.key),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ]),
                  const SizedBox(height: 16),
                  const Divider(color: AppTheme.darkBorder),
                  const SizedBox(height: 12),

                  // Items list
                  Row(children: [
                    const Text('المنتجات المرتبطة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _showAttachItems,
                      icon: const Icon(Icons.attach_file, size: 16),
                      label: const Text('ربط منتجات'),
                      style: TextButton.styleFrom(foregroundColor: AppTheme.secondary),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Builder(builder: (ctx) {
                      final items = (_shipment!['items'] as List<dynamic>?) ?? [];
                      if (items.isEmpty) {
                        return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.inventory_2_outlined, color: Colors.white12, size: 48),
                          const SizedBox(height: 8),
                          const Text('لا توجد منتجات مرتبطة', style: TextStyle(color: Colors.white38, fontSize: 13)),
                          const SizedBox(height: 12),
                          TextButton.icon(
                            onPressed: _showAttachItems,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('ربط منتجات الآن'),
                          ),
                        ]));
                      }
                      return ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.darkBorder),
                        itemBuilder: (_, i) {
                          final item = items[i] as Map<String, dynamic>;
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
                            leading: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(color: AppTheme.darkCard, borderRadius: BorderRadius.circular(8)),
                              child: const Icon(Icons.inventory_2_outlined, size: 18, color: Colors.white54),
                            ),
                            title: Text(item['product_name'] as String? ?? '—', style: const TextStyle(color: Colors.white, fontSize: 13)),
                            subtitle: Text(item['customer_name'] as String? ?? '', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: AppTheme.accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                              child: Text(item['status'] as String? ?? '', style: const TextStyle(color: AppTheme.accent, fontSize: 11)),
                            ),
                          );
                        },
                      );
                    }),
                  ),
                ]),
        ),
      ),
    );
  }
}

// ─── Attach Items Dialog ────────────────────────────────────
class _AttachItemsDialog extends ConsumerStatefulWidget {
  final String shipmentId;
  final VoidCallback onAttached;
  const _AttachItemsDialog({required this.shipmentId, required this.onAttached});
  @override
  ConsumerState<_AttachItemsDialog> createState() => _AttachItemsDialogState();
}

class _AttachItemsDialogState extends ConsumerState<_AttachItemsDialog> {
  List<Map<String, dynamic>>? _items;
  final Set<String> _selected = {};
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() { super.initState(); _loadItems(); }

  Future<void> _loadItems() async {
    setState(() { _loading = true; _error = null; });
    try {
      final items = await ref.read(externalShipmentsProvider.notifier).fetchAvailableItems();
      if (mounted) setState(() { _items = items; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = '$e'; });
    }
  }

  Future<void> _attach() async {
    if (_selected.isEmpty) return;
    setState(() => _submitting = true);
    try {
      await ref.read(externalShipmentsProvider.notifier).attachItems(
        widget.shipmentId,
        _selected.toList(),
      );
      widget.onAttached();
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('تم ربط ${_selected.length} منتج بالشحنة'),
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
      backgroundColor: AppTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Icon(Icons.attach_file_rounded, color: AppTheme.secondary, size: 22),
              const SizedBox(width: 10),
              const Expanded(child: Text('ربط منتجات بالشحنة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white))),
              IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.of(context).pop()),
            ]),
            const SizedBox(height: 8),
            const Text('المنتجات المشتراة وغير المربوطة بشحنة', style: TextStyle(color: Colors.white38, fontSize: 12)),
            const SizedBox(height: 16),
            if (_error != null) Container(
              padding: const EdgeInsets.all(10), margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: AppTheme.error.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
              child: Text(_error!, style: const TextStyle(color: AppTheme.error, fontSize: 13)),
            ),
            Expanded(
              child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (_items?.isEmpty ?? true)
                  ? const Center(child: Text('لا توجد منتجات متاحة (تأكد من أن حالتها "purchased")', style: TextStyle(color: Colors.white38, fontSize: 13), textAlign: TextAlign.center))
                  : ListView.builder(
                      itemCount: _items!.length,
                      itemBuilder: (ctx, i) {
                        final item = _items![i];
                        final id = item['id'] as String;
                        final isChecked = _selected.contains(id);
                        return CheckboxListTile(
                          value: isChecked,
                          onChanged: (v) => setState(() => v! ? _selected.add(id) : _selected.remove(id)),
                          activeColor: AppTheme.primary,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                          title: Text(item['product_name'] as String? ?? '—', style: const TextStyle(color: Colors.white, fontSize: 13)),
                          subtitle: Text(
                            '${item['customer_name'] ?? ''} · ${item['sku'] ?? ''}'.trim().replaceAll(RegExp(r' · $|^ · '), ''),
                            style: const TextStyle(color: Colors.white38, fontSize: 12),
                          ),
                        );
                      },
                    ),
            ),
            if (_selected.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(height: 48, child: ElevatedButton(
                onPressed: _submitting ? null : _attach,
                child: _submitting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text('ربط ${_selected.length} منتج'),
              )),
            ],
          ]),
        ),
      ),
    );
  }
}

// ─── Reusable Widgets ───────────────────────────────────────
class _StatusChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final Color activeColor;
  final VoidCallback? onTap;
  const _StatusChip({required this.label, required this.isActive, required this.activeColor, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isActive ? activeColor.withValues(alpha: 0.2) : AppTheme.darkCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isActive ? activeColor.withValues(alpha: 0.6) : AppTheme.darkBorder),
        ),
        child: Text(label, style: TextStyle(
          color: isActive ? activeColor : Colors.white54,
          fontSize: 12, fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
        )),
      ),
    );
  }
}
