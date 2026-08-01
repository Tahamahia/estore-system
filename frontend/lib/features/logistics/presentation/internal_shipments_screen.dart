import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:estore_app/app/theme.dart';
import 'package:estore_app/core/providers.dart';
import 'package:estore_app/core/utils/dialog_utils.dart';

class InternalShipmentsScreen extends ConsumerStatefulWidget {
  const InternalShipmentsScreen({super.key});
  @override
  ConsumerState<InternalShipmentsScreen> createState() => _InternalShipmentsScreenState();
}

class _InternalShipmentsScreenState extends ConsumerState<InternalShipmentsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(internalShipmentsProvider.notifier).fetchShipments());
  }

  void _showCreate() {
    showDialog(
      context: context,
      builder: (_) => _CreateManifestDialog(
        onCreated: () => ref.read(internalShipmentsProvider.notifier).fetchShipments(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(internalShipmentsProvider);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('الشحنات الداخلية', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white)),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: _showCreate,
            icon: const Icon(Icons.add, size: 20),
            label: const Text('مانيفست جديد'),
          ),
        ]),
        const SizedBox(height: 8),
        const Text('إدارة مانيفستات التوصيل للعملاء', style: TextStyle(color: Colors.white38, fontSize: 13)),
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
                onPressed: () => ref.read(internalShipmentsProvider.notifier).fetchShipments(),
                child: const Text('إعادة المحاولة'),
              ),
            ])),
            data: (manifests) {
              if (manifests.isEmpty) {
                return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.local_shipping_rounded, color: Colors.white12, size: 72),
                  const SizedBox(height: 16),
                  const Text('لا توجد شحنات داخلية', style: TextStyle(color: Colors.white38, fontSize: 16)),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _showCreate,
                    icon: const Icon(Icons.add, size: 20),
                    label: const Text('إنشاء أول مانيفست'),
                  ),
                ]));
              }
              return RefreshIndicator(
                onRefresh: () => ref.read(internalShipmentsProvider.notifier).fetchShipments(),
                child: ListView.separated(
                  itemCount: manifests.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (ctx, i) => _ManifestCard(
                    manifest: manifests[i],
                    onRefresh: () => ref.read(internalShipmentsProvider.notifier).fetchShipments(),
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

// ─── Status definitions ─────────────────────────────────────
const _kStatuses = [
  ('pending',               'في الانتظار',        AppTheme.accent),
  ('at_delivery_warehouse', 'مستودع التوصيل',     AppTheme.warning),
  ('out_for_delivery',      'في الطريق للزبون',   AppTheme.primary),
  ('delivered',             'تم الاستلام',         AppTheme.success),
  ('returned',              'راجع',                AppTheme.error),
];

Color _statusColor(String status) {
  for (final s in _kStatuses) { if (s.$1 == status) return s.$3; }
  return Colors.white38;
}

String _statusLabel(String status) {
  for (final s in _kStatuses) { if (s.$1 == status) return s.$2; }
  return status;
}

// ─── Manifest Card ──────────────────────────────────────────
class _ManifestCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> manifest;
  final VoidCallback onRefresh;
  const _ManifestCard({required this.manifest, required this.onRefresh});
  @override
  ConsumerState<_ManifestCard> createState() => _ManifestCardState();
}

class _ManifestCardState extends ConsumerState<_ManifestCard> {
  bool _updating = false;

  Future<void> _setStatus(String newStatus) async {
    setState(() => _updating = true);
    try {
      await ref.read(internalShipmentsProvider.notifier).updateShipment(
        widget.manifest['id'] as String,
        {'status': newStatus},
      );
      widget.onRefresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppTheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  void _showDetail() {
    showDialog(
      context: context,
      builder: (_) => _ManifestDetailDialog(
        manifestId: widget.manifest['id'] as String,
        onRefresh: widget.onRefresh,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.manifest;
    final status = m['status'] as String? ?? 'pending';
    final company = m['delivery_company'] as String? ?? 'شركة غير محددة';
    final orderCount = (m['order_count'] as num?)?.toInt() ?? 0;
    final color = _statusColor(status);
    final createdAt = (m['created_at'] as String? ?? '').length >= 10
      ? (m['created_at'] as String).substring(0, 10)
      : (m['created_at'] as String? ?? '');

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(children: [
        // Card header
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.local_shipping_rounded, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(company, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
              Text('$orderCount طلب · $createdAt', style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withValues(alpha: 0.4)),
              ),
              child: Text(_statusLabel(status), style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),

        // Status pipeline
        if (status != 'delivered' && status != 'returned')
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: AppTheme.darkBorder))),
            child: _updating
              ? const Center(child: SizedBox(height: 32, child: CircularProgressIndicator(strokeWidth: 2)))
              : _PipelineBar(currentStatus: status, onAdvance: _setStatus),
          ),

        // Footer
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: AppTheme.darkBorder))),
          child: Row(children: [
            Icon(Icons.receipt_long_outlined, color: Colors.white38, size: 15),
            const SizedBox(width: 6),
            Text('$orderCount طلب', style: const TextStyle(color: Colors.white54, fontSize: 12)),
            const Spacer(),
            TextButton.icon(
              onPressed: _showDetail,
              icon: const Icon(Icons.open_in_new, size: 15),
              label: const Text('التفاصيل', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ─── Pipeline Bar ───────────────────────────────────────────
class _PipelineBar extends StatelessWidget {
  final String currentStatus;
  final void Function(String) onAdvance;
  const _PipelineBar({required this.currentStatus, required this.onAdvance});

  @override
  Widget build(BuildContext context) {
    const pipeline = ['pending', 'at_delivery_warehouse', 'out_for_delivery'];
    final currentIdx = pipeline.indexOf(currentStatus);

    return Column(children: [
      Row(children: [
        for (int i = 0; i < pipeline.length; i++) ...[
          Expanded(
            child: GestureDetector(
              onTap: i > currentIdx ? () => onAdvance(pipeline[i]) : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: i <= currentIdx
                    ? _statusColor(pipeline[i]).withValues(alpha: 0.2)
                    : AppTheme.darkCard,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: i <= currentIdx
                      ? _statusColor(pipeline[i]).withValues(alpha: 0.5)
                      : AppTheme.darkBorder,
                  ),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                    i < currentIdx ? Icons.check_circle_rounded
                      : i == currentIdx ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                    size: 16,
                    color: i <= currentIdx ? _statusColor(pipeline[i]) : Colors.white24,
                  ),
                  const SizedBox(height: 2),
                  Text(_statusLabel(pipeline[i]), style: TextStyle(
                    color: i <= currentIdx ? Colors.white : Colors.white24,
                    fontSize: 10, fontWeight: i == currentIdx ? FontWeight.w600 : FontWeight.w400,
                  ), textAlign: TextAlign.center),
                ]),
              ),
            ),
          ),
          if (i < pipeline.length - 1)
            Container(width: 4, height: 2, color: Colors.white12),
        ],
      ]),
      const SizedBox(height: 10),
      // Action buttons for terminal states
      Row(children: [
        Expanded(child: OutlinedButton.icon(
          onPressed: () => onAdvance('delivered'),
          icon: const Icon(Icons.check_circle_outline, size: 16, color: AppTheme.success),
          label: const Text('تم الاستلام', style: TextStyle(color: AppTheme.success, fontSize: 12)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppTheme.success),
            padding: const EdgeInsets.symmetric(vertical: 8),
          ),
        )),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton.icon(
          onPressed: () => onAdvance('returned'),
          icon: const Icon(Icons.keyboard_return_rounded, size: 16, color: AppTheme.error),
          label: const Text('راجع', style: TextStyle(color: AppTheme.error, fontSize: 12)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppTheme.error),
            padding: const EdgeInsets.symmetric(vertical: 8),
          ),
        )),
      ]),
    ]);
  }
}

// ─── Create Manifest Dialog ─────────────────────────────────
class _CreateManifestDialog extends ConsumerStatefulWidget {
  final VoidCallback onCreated;
  const _CreateManifestDialog({required this.onCreated});
  @override
  ConsumerState<_CreateManifestDialog> createState() => _CreateManifestDialogState();
}

class _CreateManifestDialogState extends ConsumerState<_CreateManifestDialog> {
  final _companyCtrl = TextEditingController();
  final _notesCtrl   = TextEditingController();
  List<Map<String, dynamic>>? _availableOrders;
  final Set<String> _selectedOrderIds = {};
  bool _loadingOrders = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() { super.initState(); _loadOrders(); }

  @override
  void dispose() { _companyCtrl.dispose(); _notesCtrl.dispose(); super.dispose(); }

  Future<void> _loadOrders() async {
    setState(() { _loadingOrders = true; _error = null; });
    try {
      final orders = await ref.read(internalShipmentsProvider.notifier).fetchAvailableOrders();
      if (mounted) setState(() { _availableOrders = orders; _loadingOrders = false; });
    } catch (e) {
      if (mounted) setState(() { _loadingOrders = false; _error = '$e'; });
    }
  }

  Future<void> _submit() async {
    if (_companyCtrl.text.trim().isEmpty) { setState(() => _error = 'اسم شركة التوصيل مطلوب'); return; }
    setState(() { _submitting = true; _error = null; });
    try {
      await ref.read(internalShipmentsProvider.notifier).createShipment({
        'id': const Uuid().v4(),
        'delivery_company': _companyCtrl.text.trim(),
        if (_notesCtrl.text.trim().isNotEmpty) 'notes': _notesCtrl.text.trim(),
        if (_selectedOrderIds.isNotEmpty) 'order_ids': _selectedOrderIds.toList(),
      });
      widget.onCreated();
      if (mounted) Navigator.of(context).pop();
    } catch (e) { setState(() => _error = '$e'); }
    finally { if (mounted) setState(() => _submitting = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 520, maxHeight: dialogMaxHeight(context, cap: 680)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.local_shipping_rounded, color: AppTheme.primary, size: 22),
              ),
              const SizedBox(width: 12),
              const Text('مانيفست توصيل جديد', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
            ]),
            const SizedBox(height: 20),
            if (_error != null) Container(
              padding: const EdgeInsets.all(10), margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: AppTheme.error.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
              child: Text(_error!, style: const TextStyle(color: AppTheme.error, fontSize: 13)),
            ),
            TextField(
              controller: _companyCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'شركة التوصيل *', prefixIcon: Icon(Icons.business_rounded)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'ملاحظات', prefixIcon: Icon(Icons.notes_rounded)),
            ),
            const SizedBox(height: 16),
            Row(children: [
              const Text('الطلبات الجاهزة للتوصيل', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              const Spacer(),
              if (_selectedOrderIds.isNotEmpty)
                Text('${_selectedOrderIds.length} محدد', style: const TextStyle(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.darkCard.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.darkBorder),
                ),
                child: _loadingOrders
                  ? const Center(child: CircularProgressIndicator())
                  : (_availableOrders?.isEmpty ?? true)
                    ? const Center(child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('لا توجد طلبات جاهزة للتوصيل\n(يجب أن تكون بحالة "sorted" أو "ready_dispatch")',
                          style: TextStyle(color: Colors.white38, fontSize: 13), textAlign: TextAlign.center),
                      ))
                    : ListView.builder(
                        itemCount: _availableOrders!.length,
                        itemBuilder: (ctx, i) {
                          final order = _availableOrders![i];
                          final id = order['id'] as String;
                          final isChecked = _selectedOrderIds.contains(id);
                          final name = order['customer_name'] as String? ?? '—';
                          final city = order['customer_city'] as String? ?? '';
                          final area = order['customer_area'] as String? ?? '';
                          final location = [city, area].where((s) => s.isNotEmpty).join(' - ');
                          final itemCount = (order['item_count'] as num?)?.toInt() ?? 0;

                          return CheckboxListTile(
                            value: isChecked,
                            onChanged: (v) => setState(() => v! ? _selectedOrderIds.add(id) : _selectedOrderIds.remove(id)),
                            activeColor: AppTheme.primary,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                            title: Text(name, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                            subtitle: Text(
                              [if (location.isNotEmpty) location, '$itemCount منتج'].join(' · '),
                              style: const TextStyle(color: Colors.white38, fontSize: 12),
                            ),
                          );
                        },
                      ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(height: 48, child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(_selectedOrderIds.isEmpty
                    ? 'إنشاء مانيفست (بدون طلبات)'
                    : 'إنشاء مانيفست (${_selectedOrderIds.length} طلب)'),
            )),
          ]),
        ),
      ),
    );
  }
}

// ─── Manifest Detail Dialog ─────────────────────────────────
class _ManifestDetailDialog extends ConsumerStatefulWidget {
  final String manifestId;
  final VoidCallback onRefresh;
  const _ManifestDetailDialog({required this.manifestId, required this.onRefresh});
  @override
  ConsumerState<_ManifestDetailDialog> createState() => _ManifestDetailDialogState();
}

class _ManifestDetailDialogState extends ConsumerState<_ManifestDetailDialog> {
  Map<String, dynamic>? _manifest;
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await ref.read(internalShipmentsProvider.notifier).getShipment(widget.manifestId);
      if (mounted) setState(() { _manifest = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = '$e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 520, maxHeight: dialogMaxHeight(context, cap: 580)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: AppTheme.error)))
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    const Icon(Icons.local_shipping_rounded, color: AppTheme.primary, size: 22),
                    const SizedBox(width: 10),
                    Expanded(child: Text(
                      _manifest!['delivery_company'] as String? ?? '—',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                    )),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _statusColor(_manifest!['status'] as String? ?? 'pending').withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _statusLabel(_manifest!['status'] as String? ?? 'pending'),
                        style: TextStyle(color: _statusColor(_manifest!['status'] as String? ?? 'pending'), fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.of(context).pop()),
                  ]),
                  const SizedBox(height: 16),
                  const Divider(color: AppTheme.darkBorder),
                  const SizedBox(height: 12),
                  const Text('الطلبات في هذا المانيفست', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Builder(builder: (ctx) {
                      final orders = (_manifest!['orders'] as List<dynamic>?) ?? [];
                      if (orders.isEmpty) {
                        return const Center(child: Text('لا توجد طلبات مرتبطة', style: TextStyle(color: Colors.white38)));
                      }
                      return ListView.separated(
                        itemCount: orders.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.darkBorder),
                        itemBuilder: (_, i) {
                          final order = orders[i] as Map<String, dynamic>;
                          final name = order['customer_name'] as String? ?? '—';
                          final phone = order['customer_phone'] as String? ?? '';
                          final city = order['customer_city'] as String? ?? '';
                          final area = order['customer_area'] as String? ?? '';
                          final location = [city, area].where((s) => s.isNotEmpty).join(' - ');
                          final itemCount = (order['item_count'] as num?)?.toInt() ?? 0;
                          final status = order['status'] as String? ?? '';
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
                            title: Text(name, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                            subtitle: Text(
                              [if (phone.isNotEmpty) phone, if (location.isNotEmpty) location, '$itemCount منتج'].join(' · '),
                              style: const TextStyle(color: Colors.white38, fontSize: 12),
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: _statusColor(status).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                              child: Text(_statusLabel(status), style: TextStyle(color: _statusColor(status), fontSize: 11)),
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
