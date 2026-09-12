import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:estore_app/app/theme.dart';
import 'package:estore_app/core/providers.dart';
import 'package:estore_app/core/utils/dialog_utils.dart';

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

  // Status is now DERIVED — 'arrived_at_warehouse' when every live item has
  // moved past shipped, else 'in_transit'. Only two states matter for the UI.
  Color _derivedStatusColor(String status) =>
      status == 'arrived_at_warehouse' ? AppTheme.success : AppTheme.accent;

  String _derivedStatusLabel(String status) =>
      status == 'arrived_at_warehouse' ? 'وصلت' : 'في الطريق';

  Future<void> _sync(BuildContext context) async {
    final notifier = ProviderScope.containerOf(context).read(externalShipmentsProvider.notifier);
    setState(() => _syncing = true);
    try {
      final result = await notifier.syncTracking(widget.shipment['id'] as String);
      if (!context.mounted) return;
      final tracking = result['tracking'] as Map<String, dynamic>? ?? {};
      final rawEvents = result['tracking_events'] as List<dynamic>? ?? [];
      final events = rawEvents.map((e) => e as Map<String, dynamic>).toList();
      widget.onRefresh();
      showDialog(
        context: context,
        builder: (_) => _TrackingTimelineDialog(
          courier: tracking['courier'] as String? ?? '',
          trackingNumber: widget.shipment['tracking_number'] as String? ?? '',
          engine: tracking['engine'] as String? ?? '',
          events: events,
        ),
      );
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

  Future<void> _delete(BuildContext context) async {
    final notifier = ProviderScope.containerOf(context).read(externalShipmentsProvider.notifier);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.darkSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('حذف الشحنة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: const Text(
          'هل أنت متأكد من الحذف؟ سيتم فك ارتباط جميع المنتجات المرتبطة وإعادة حالتها إلى "مشتري".',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    // Guard: dialog close is async; widget may have been disposed
    if (!context.mounted) return;
    if (confirm != true) return;
    try {
      await notifier.deleteShipment(widget.shipment['id'] as String);
      // deleteShipment internally calls fetchShipments() which rebuilds the list
      // and may dispose this card — guard before any further context use
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تم حذف الشحنة'),
        backgroundColor: AppTheme.error,
      ));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('خطأ في الحذف: $e'),
        backgroundColor: AppTheme.error,
      ));
    }
  }

  void _editTracking(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _EditTrackingDialog(
        shipmentId: widget.shipment['id'] as String,
        currentTracking: widget.shipment['tracking_number'] as String? ?? '',
        onSaved: widget.onRefresh,
      ),
    );
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
    final derivedStatus = s['manual_status'] as String? ?? 'in_transit';
    final expected = (s['expected_count'] as num?)?.toInt() ?? 0;
    final arrived = (s['arrived_count'] as num?)?.toInt() ?? 0;
    final sortedCount = (s['sorted_count'] as num?)?.toInt() ?? 0;
    final missingCount = (s['missing_count'] as num?)?.toInt() ?? 0;
    final statusColor = _derivedStatusColor(derivedStatus);
    final isReceived = derivedStatus == 'arrived_at_warehouse';

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
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
              const SizedBox(height: 6),
              // Derived progress line
              Text(
                'وصل $arrived/$expected · فُرز $sortedCount/$expected',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
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
            // Derived status badge
            Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                ),
                child: Text(_derivedStatusLabel(derivedStatus),
                    style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 3),
              const Text('تُحسب تلقائياً من حالة القطع',
                  style: TextStyle(color: Colors.white38, fontSize: 10)),
              if (isReceived && missingCount > 0) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.error.withValues(alpha: 0.4)),
                  ),
                  child: Text('$missingCount مفقود',
                      style: const TextStyle(color: AppTheme.error, fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ],
            ]),
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
            Text('$expected منتج', style: const TextStyle(color: Colors.white54, fontSize: 13)),
            const Spacer(),
            // Delete button
            IconButton(
              onPressed: () => _delete(context),
              icon: const Icon(Icons.delete_outline, size: 18),
              color: AppTheme.error,
              tooltip: 'حذف الشحنة',
            ),
            const SizedBox(width: 4),
            // Edit tracking number button
            IconButton(
              onPressed: () => _editTracking(context),
              icon: const Icon(Icons.edit_outlined, size: 18),
              color: Colors.white54,
              tooltip: 'تعديل رقم التتبع',
            ),
            // Sync / Track button
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
      insetPadding: EdgeInsets.symmetric(horizontal: isMobile(context) ? 8 : 40, vertical: 24),
      backgroundColor: AppTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: dialogMaxWidth(context, desktopMax: 440)),
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
// Inline reconciliation + inline attach — no nested dialogs.
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
  bool _receiving = false;

  // Inline attach section state
  bool _attachOpen = false;
  List<Map<String, dynamic>>? _availableOrders;
  final Set<String> _selectedOrderIds = {};
  bool _attachLoading = false;
  bool _attaching = false;

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

  Future<void> _receive() async {
    setState(() => _receiving = true);
    try {
      await ref.read(externalShipmentsProvider.notifier).receiveShipment(widget.shipmentId);
      widget.onRefresh();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تم استلام الشحنة — الآن راجع القطع الناقصة'),
          backgroundColor: AppTheme.success,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppTheme.error));
      }
    } finally {
      if (mounted) setState(() => _receiving = false);
    }
  }

  Future<void> _markLost(String itemId, String productName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.darkSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('تعليم كمفقود', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: Text(
          'تعليم "$productName" كمفقود سيلغي القطعة ويكتب "[مفقود في الشحنة]" في ملاحظاتها. متأكد؟',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('تعليم كمفقود'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await ref.read(externalShipmentsProvider.notifier).markItemLost(widget.shipmentId, itemId);
      widget.onRefresh();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppTheme.error));
      }
    }
  }

  Future<void> _toggleAttach() async {
    setState(() => _attachOpen = !_attachOpen);
    if (_attachOpen && _availableOrders == null) {
      setState(() => _attachLoading = true);
      try {
        final orders = await ref.read(externalShipmentsProvider.notifier).fetchAvailableOrders();
        if (mounted) setState(() { _availableOrders = orders; _attachLoading = false; });
      } catch (e) {
        if (mounted) {
          setState(() => _attachLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppTheme.error));
        }
      }
    }
  }

  Future<void> _attachSelected() async {
    if (_selectedOrderIds.isEmpty) return;
    setState(() => _attaching = true);
    try {
      final count = _selectedOrderIds.length;
      await ref.read(externalShipmentsProvider.notifier).attachOrders(
        widget.shipmentId, _selectedOrderIds.toList(),
      );
      widget.onRefresh();
      if (!mounted) return;
      setState(() {
        _selectedOrderIds.clear();
        _availableOrders = null; // force refetch on next open
        _attachOpen = false;
      });
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('تم ربط $count طلبية بالشحنة'),
          backgroundColor: AppTheme.success,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppTheme.error));
      }
    } finally {
      if (mounted) setState(() => _attaching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: isMobile(context) ? 8 : 40, vertical: 24),
      backgroundColor: AppTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: dialogMaxWidth(context, desktopMax: 560), maxHeight: dialogMaxHeight(context, cap: 720)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: AppTheme.error)))
              : _buildDetail(),
        ),
      ),
    );
  }

  Widget _buildDetail() {
    final s = _shipment!;
    final derivedStatus = s['manual_status'] as String? ?? 'in_transit';
    final expected = (s['expected_count'] as num?)?.toInt() ?? 0;
    final arrived = (s['arrived_count'] as num?)?.toInt() ?? 0;
    final sortedCount = (s['sorted_count'] as num?)?.toInt() ?? 0;
    final missingCount = (s['missing_count'] as num?)?.toInt() ?? 0;
    final isReceived = derivedStatus == 'arrived_at_warehouse';
    final statusColor = isReceived ? AppTheme.success : AppTheme.accent;
    final items = (s['items'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();

    // Group items by order for the reconciliation view.
    final byOrder = <String, List<Map<String, dynamic>>>{};
    for (final it in items) {
      final oid = it['order_id'] as String? ?? '—';
      byOrder.putIfAbsent(oid, () => []).add(it);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Header
      Row(children: [
        const Icon(Icons.flight_land_rounded, color: AppTheme.primary, size: 22),
        const SizedBox(width: 10),
        Expanded(child: Text(
          s['tracking_number'] as String? ?? '—',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16, fontFamily: 'monospace'),
        )),
        IconButton(
          icon: const Icon(Icons.close, color: Colors.white54),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ]),
      if (s['courier_code'] != null) ...[
        const SizedBox(height: 4),
        Text(s['courier_code'] as String, style: const TextStyle(color: Colors.white54, fontSize: 13)),
      ],
      const SizedBox(height: 12),
      // Derived badge + subtitle
      Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: statusColor.withValues(alpha: 0.4)),
          ),
          child: Text(isReceived ? 'وصلت' : 'في الطريق',
              style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 8),
        const Expanded(child: Text('تُحسب تلقائياً من حالة القطع',
            style: TextStyle(color: Colors.white38, fontSize: 11))),
      ]),
      const SizedBox(height: 4),
      Text(
          'وصل $arrived/$expected · فُرز $sortedCount/$expected'
          '${isReceived && missingCount > 0 ? '  ·  ناقص $missingCount' : ''}',
          style: TextStyle(
              color: isReceived && missingCount > 0 ? AppTheme.error : Colors.white54,
              fontSize: 12,
              fontWeight: isReceived && missingCount > 0 ? FontWeight.w700 : FontWeight.w400)),
      const SizedBox(height: 16),
      // Receive action — visible only while in-transit and there is anything to receive.
      if (!isReceived && expected > 0)
        SizedBox(height: 44, child: ElevatedButton.icon(
          onPressed: _receiving ? null : _receive,
          icon: _receiving
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.inbox_rounded, size: 18),
          label: const Text('استلام الشحنة'),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
        )),
      if (!isReceived && expected > 0) const SizedBox(height: 12),

      // Attach section (inline)
      InkWell(
        onTap: _toggleAttach,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.darkCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.darkBorder),
          ),
          child: Row(children: [
            const Icon(Icons.attach_file_rounded, color: AppTheme.secondary, size: 18),
            const SizedBox(width: 8),
            const Expanded(child: Text('ربط طلبيات',
                style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600))),
            Icon(_attachOpen ? Icons.expand_less : Icons.expand_more, color: Colors.white54, size: 20),
          ]),
        ),
      ),
      if (_attachOpen) _buildAttachInline(),

      const SizedBox(height: 12),
      const Divider(color: AppTheme.darkBorder),
      const SizedBox(height: 8),
      const Text('القطع', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Expanded(
        child: items.isEmpty
          ? const Center(child: Text('لا توجد قطع مرتبطة',
              style: TextStyle(color: Colors.white38, fontSize: 13)))
          : ListView(
              children: [
                for (final entry in byOrder.entries) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Text('طلبية #${entry.key.length > 8 ? entry.key.substring(0, 8) : entry.key}',
                        style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
                  for (final item in entry.value)
                    _ReconItemRow(
                      item: item,
                      canMarkLost: isReceived && (item['status'] as String? ?? '') == 'shipped',
                      onMarkLost: () => _markLost(
                        item['id'] as String,
                        item['product_name'] as String? ?? '—',
                      ),
                    ),
                ],
              ],
            ),
      ),
    ]);
  }

  Widget _buildAttachInline() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.darkCard.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('الطلبيات التي تحتوي على قطع "مشتراة" وغير مربوطة بشحنة',
            style: TextStyle(color: Colors.white38, fontSize: 11)),
        const SizedBox(height: 8),
        if (_attachLoading)
          const Padding(padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
        else if ((_availableOrders?.isEmpty ?? true))
          const Padding(padding: EdgeInsets.all(12),
              child: Text('لا توجد طلبيات متاحة',
                  style: TextStyle(color: Colors.white38, fontSize: 12), textAlign: TextAlign.center))
        else ...[
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _availableOrders!.length,
              itemBuilder: (_, i) {
                final order = _availableOrders![i];
                final orderId = order['id'] as String;
                final shortId = orderId.length > 8 ? orderId.substring(0, 8) : orderId;
                final customerName = order['customer_name'] as String? ?? '—';
                final phone = order['customer_phone'] as String? ?? '';
                final itemCount = (order['purchased_item_count'] as num?)?.toInt() ?? 0;
                final isChecked = _selectedOrderIds.contains(orderId);
                return CheckboxListTile(
                  dense: true,
                  value: isChecked,
                  onChanged: (v) => setState(() => v! ? _selectedOrderIds.add(orderId) : _selectedOrderIds.remove(orderId)),
                  activeColor: AppTheme.primary,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                  title: Text('#$shortId — $customerName',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
                  subtitle: Text([if (phone.isNotEmpty) phone, '$itemCount قطعة'].join(' · '),
                      style: const TextStyle(color: Colors.white38, fontSize: 11)),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(height: 40, child: ElevatedButton(
            onPressed: (_selectedOrderIds.isEmpty || _attaching) ? null : _attachSelected,
            child: _attaching
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(_selectedOrderIds.isEmpty ? 'اختر طلبيات' : 'ربط ${_selectedOrderIds.length} طلبية'),
          )),
        ],
      ]),
    );
  }
}

// Reconciliation row: name + customer + status chip, red-highlighted with
// a "تعليم كمفقود" action when the shipment is received but the item is
// still 'shipped'.
class _ReconItemRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool canMarkLost;
  final VoidCallback onMarkLost;
  const _ReconItemRow({required this.item, required this.canMarkLost, required this.onMarkLost});

  @override
  Widget build(BuildContext context) {
    final status = item['status'] as String? ?? '';
    final isMissing = canMarkLost; // received & still shipped
    final chipColor = _statusColor(status);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isMissing ? AppTheme.error.withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isMissing ? AppTheme.error.withValues(alpha: 0.35) : AppTheme.darkBorder),
      ),
      child: Row(children: [
        Icon(
          isMissing ? Icons.report_gmailerrorred_rounded : Icons.inventory_2_outlined,
          size: 18,
          color: isMissing ? AppTheme.error : Colors.white54,
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item['product_name'] as String? ?? '—',
              style: const TextStyle(color: Colors.white, fontSize: 13)),
          Text(item['customer_name'] as String? ?? '',
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: chipColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(status, style: TextStyle(color: chipColor, fontSize: 11)),
        ),
        if (canMarkLost) ...[
          const SizedBox(width: 6),
          TextButton(
            onPressed: onMarkLost,
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.error,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
              minimumSize: const Size(0, 28),
            ),
            child: const Text('تعليم كمفقود', style: TextStyle(fontSize: 11)),
          ),
        ],
      ]),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'shipped':            return AppTheme.warning;
      case 'arrived_warehouse':  return AppTheme.accent;
      case 'sorted':
      case 'ready_dispatch':
      case 'dispatched':
      case 'delivered':          return AppTheme.success;
      case 'cancelled':
      case 'refunded':           return AppTheme.error;
      default:                   return Colors.white38;
    }
  }
}

// ─── Edit Tracking Number Dialog ───────────────────────────
class _EditTrackingDialog extends ConsumerStatefulWidget {
  final String shipmentId;
  final String currentTracking;
  final VoidCallback onSaved;
  const _EditTrackingDialog({required this.shipmentId, required this.currentTracking, required this.onSaved});
  @override
  ConsumerState<_EditTrackingDialog> createState() => _EditTrackingDialogState();
}

class _EditTrackingDialogState extends ConsumerState<_EditTrackingDialog> {
  late final TextEditingController _ctrl;
  bool _loading = false;
  String? _error;

  @override
  void initState() { super.initState(); _ctrl = TextEditingController(text: widget.currentTracking); }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    final value = _ctrl.text.trim();
    if (value.isEmpty) { setState(() => _error = 'رقم التتبع مطلوب'); return; }
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(externalShipmentsProvider.notifier).updateShipment(
        widget.shipmentId,
        {'tracking_number': value},
      );
      widget.onSaved();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() { _loading = false; _error = '$e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: isMobile(context) ? 8 : 40, vertical: 24),
      backgroundColor: AppTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: dialogMaxWidth(context, desktopMax: 400)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('تعديل رقم التتبع', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white)),
            const SizedBox(height: 20),
            if (_error != null) Container(
              padding: const EdgeInsets.all(10), margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: AppTheme.error.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
              child: Text(_error!, style: const TextStyle(color: AppTheme.error, fontSize: 13)),
            ),
            TextField(
              controller: _ctrl,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
              decoration: const InputDecoration(labelText: 'رقم التتبع', prefixIcon: Icon(Icons.qr_code_rounded)),
            ),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
              )),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton(
                onPressed: _loading ? null : _save,
                child: _loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('حفظ'),
              )),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ─── Tracking Timeline Dialog ───────────────────────────────
class _TrackingTimelineDialog extends StatelessWidget {
  final String courier;
  final String trackingNumber;
  final String engine;
  final List<Map<String, dynamic>> events;
  const _TrackingTimelineDialog({
    required this.courier,
    required this.trackingNumber,
    required this.engine,
    required this.events,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: isMobile(context) ? 8 : 40, vertical: 24),
      backgroundColor: AppTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: dialogMaxWidth(context, desktopMax: 500), maxHeight: dialogMaxHeight(context, cap: 580)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Icon(Icons.radar_rounded, color: AppTheme.accent, size: 22),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('مسار الشحنة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                if (courier.isNotEmpty)
                  Text(courier, style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ])),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ]),
            if (trackingNumber.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(trackingNumber, style: const TextStyle(color: Colors.white38, fontSize: 12, fontFamily: 'monospace')),
            ],
            if (engine.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(engine, style: const TextStyle(color: Colors.white24, fontSize: 11)),
            ],
            const SizedBox(height: 16),
            const Divider(color: AppTheme.darkBorder),
            const SizedBox(height: 8),
            Expanded(
              child: events.isEmpty
                ? const Center(child: Text(
                    'لا توجد تفاصيل دقيقة متاحة حالياً',
                    style: TextStyle(color: Colors.white38, fontSize: 14),
                    textAlign: TextAlign.center,
                  ))
                : ListView.builder(
                    itemCount: events.length,
                    itemBuilder: (_, i) {
                      final e = events[i];
                      final isFirst = i == 0;
                      final date = e['date'] as String? ?? '';
                      final desc = e['description'] as String? ?? '';
                      final loc = e['location'] as String?;
                      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Column(children: [
                          Container(
                            width: 12, height: 12,
                            decoration: BoxDecoration(
                              color: isFirst ? AppTheme.accent : AppTheme.darkCard,
                              shape: BoxShape.circle,
                              border: Border.all(color: isFirst ? AppTheme.accent : AppTheme.darkBorder, width: 2),
                            ),
                          ),
                          if (i < events.length - 1)
                            Container(width: 2, height: 52, color: AppTheme.darkBorder),
                        ]),
                        const SizedBox(width: 12),
                        Expanded(child: Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(desc, style: TextStyle(
                              color: isFirst ? Colors.white : Colors.white70,
                              fontSize: 13,
                              fontWeight: isFirst ? FontWeight.w600 : FontWeight.w400,
                            )),
                            if (loc != null && loc.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Row(children: [
                                const Icon(Icons.location_on_outlined, size: 12, color: Colors.white38),
                                const SizedBox(width: 4),
                                Flexible(child: Text(loc, style: const TextStyle(color: Colors.white38, fontSize: 11))),
                              ]),
                            ],
                            const SizedBox(height: 2),
                            Text(date, style: const TextStyle(color: Colors.white24, fontSize: 11)),
                          ]),
                        )),
                      ]);
                    },
                  ),
            ),
          ]),
        ),
      ),
    );
  }
}

