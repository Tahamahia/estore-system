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
              const Text('تعذّر تحميل الشحنات', style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              const Text('تحقق من الاتصال بالإنترنت وأعد المحاولة', style: TextStyle(color: Colors.white38, fontSize: 13), textAlign: TextAlign.center),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => ref.invalidate(internalShipmentsProvider),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('إعادة المحاولة'),
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

// ─── Status labels ──────────────────────────────────────────
// The manifest status is now DERIVED: 'delivered' is set automatically the
// moment every attached order is delivered (see buildRecomputeInternalShipmentStmt).
// Admins only ever explicitly move pending → out_for_delivery.
Color _statusColor(String status) {
  switch (status) {
    case 'delivered':             return AppTheme.success;
    case 'out_for_delivery':      return AppTheme.primary;
    case 'at_delivery_warehouse': return AppTheme.warning;
    case 'returned':              return AppTheme.error;
    default:                      return AppTheme.accent;
  }
}

String _statusLabel(String status) {
  switch (status) {
    case 'delivered':             return 'مكتمل';
    case 'out_for_delivery':      return 'خرج للتوصيل';
    case 'at_delivery_warehouse': return 'مستودع التوصيل';
    case 'returned':              return 'مُرجَع';
    default:                      return 'في الانتظار';
  }
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

  Future<void> _dispatch() async {
    setState(() => _updating = true);
    try {
      await ref.read(internalShipmentsProvider.notifier).updateShipment(
        widget.manifest['id'] as String,
        {'status': 'out_for_delivery'},
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

  void _openDetail() {
    final id = widget.manifest['id'] as String;
    if (isMobile(context)) {
      Navigator.of(context).push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _ManifestDetailPage(manifestId: id, onRefresh: widget.onRefresh),
      ));
    } else {
      showDialog(
        context: context,
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          backgroundColor: AppTheme.darkSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: dialogMaxWidth(context, desktopMax: 560),
              maxHeight: dialogMaxHeight(context, cap: 720),
            ),
            child: _ManifestDetailPage(
              manifestId: id,
              onRefresh: widget.onRefresh,
              embedded: true,
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.manifest;
    final status = m['status'] as String? ?? 'pending';
    final company = m['delivery_company'] as String? ?? 'شركة غير محددة';
    final driverName = (m['driver_name'] as String?)?.trim();
    final orderCount = (m['order_count'] as num?)?.toInt() ?? 0;
    final cashExpected = (m['cash_expected'] as num?)?.toDouble() ?? 0;
    final cashHandedOver = (m['cash_handed_over'] as num?)?.toDouble();
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
              Text(
                [if (driverName != null && driverName.isNotEmpty) 'المندوب: $driverName', '$orderCount طلب', createdAt]
                  .where((s) => s.isNotEmpty).join(' · '),
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
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

        // One explicit admin transition: pending → out_for_delivery.
        // Everything after that (delivered, cash) is derived from per-door events.
        if (status == 'pending' || status == 'at_delivery_warehouse')
          Container(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: AppTheme.darkBorder))),
            child: SizedBox(
              width: double.infinity,
              height: 36,
              child: ElevatedButton.icon(
                onPressed: _updating ? null : _dispatch,
                icon: _updating
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.local_shipping_outlined, size: 16),
                label: const Text('خرج للتوصيل'),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
              ),
            ),
          ),

        // Cash row (only when the manifest has settled to delivered)
        if (status == 'delivered')
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: AppTheme.darkBorder))),
            child: Row(children: [
              const Icon(Icons.payments_outlined, color: Colors.white54, size: 15),
              const SizedBox(width: 6),
              Text('متوقع: ${cashExpected.toStringAsFixed(0)} د.ل',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
              const Spacer(),
              _handoverChip(cashHandedOver, cashExpected),
            ]),
          ),

        // Footer
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: AppTheme.darkBorder))),
          child: Row(children: [
            const Icon(Icons.receipt_long_outlined, color: Colors.white38, size: 15),
            const SizedBox(width: 6),
            Text('$orderCount طلب', style: const TextStyle(color: Colors.white54, fontSize: 12)),
            const Spacer(),
            TextButton.icon(
              onPressed: _openDetail,
              icon: const Icon(Icons.open_in_new, size: 15),
              label: const Text('التفاصيل', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _handoverChip(double? handed, double expected) {
    if (handed == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: AppTheme.warning.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
        child: const Text('لم يُسلَّم الكاش',
          style: TextStyle(color: AppTheme.warning, fontSize: 11, fontWeight: FontWeight.w600)),
      );
    }
    final diff = handed - expected;
    final shortfall = diff < -0.5;
    final surplus = diff > 0.5;
    final bg = shortfall ? AppTheme.error : AppTheme.success;
    final label = shortfall
      ? 'تم تسليم ${handed.toStringAsFixed(0)} د.ل (ناقص ${(-diff).toStringAsFixed(0)})'
      : surplus
        ? 'تم تسليم ${handed.toStringAsFixed(0)} د.ل (زائد ${diff.toStringAsFixed(0)})'
        : 'تم تسليم ${handed.toStringAsFixed(0)} د.ل';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: TextStyle(color: bg, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

// ─── Create Manifest Dialog ─────────────────────────────────
// Kept short (company + driver + notes only). Attaching orders happens
// inline inside the manifest detail — no nested-dialog attach flow.
class _CreateManifestDialog extends ConsumerStatefulWidget {
  final VoidCallback onCreated;
  const _CreateManifestDialog({required this.onCreated});
  @override
  ConsumerState<_CreateManifestDialog> createState() => _CreateManifestDialogState();
}

class _CreateManifestDialogState extends ConsumerState<_CreateManifestDialog> {
  final _companyCtrl = TextEditingController();
  final _driverCtrl  = TextEditingController();
  final _notesCtrl   = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() { _companyCtrl.dispose(); _driverCtrl.dispose(); _notesCtrl.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (_companyCtrl.text.trim().isEmpty) { setState(() => _error = 'اسم شركة التوصيل مطلوب'); return; }
    setState(() { _submitting = true; _error = null; });
    try {
      await ref.read(internalShipmentsProvider.notifier).createShipment({
        'id': const Uuid().v4(),
        'delivery_company': _companyCtrl.text.trim(),
        if (_driverCtrl.text.trim().isNotEmpty) 'driver_name': _driverCtrl.text.trim(),
        if (_notesCtrl.text.trim().isNotEmpty) 'notes': _notesCtrl.text.trim(),
      });
      widget.onCreated();
      if (mounted) Navigator.of(context).pop();
    } catch (e) { setState(() => _error = '$e'); }
    finally { if (mounted) setState(() => _submitting = false); }
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
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
              controller: _driverCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'اسم المندوب (اختياري)', prefixIcon: Icon(Icons.person_outline)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'ملاحظات', prefixIcon: Icon(Icons.notes_rounded)),
            ),
            const SizedBox(height: 20),
            SizedBox(height: 48, child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('إنشاء المانيفست'),
            )),
            const SizedBox(height: 6),
            const Text('يمكنك ربط الطلبات من داخل المانيفست بعد إنشائه.',
                style: TextStyle(color: Colors.white38, fontSize: 11), textAlign: TextAlign.center),
          ]),
        ),
      ),
    );
  }
}

// ─── Manifest Detail — full-screen on mobile, dialog on desktop ───
class _ManifestDetailPage extends ConsumerStatefulWidget {
  final String manifestId;
  final VoidCallback onRefresh;
  /// When true, the widget renders inside an existing Dialog and skips its
  /// own Scaffold/AppBar so the desktop dialog stays compact.
  final bool embedded;
  const _ManifestDetailPage({
    required this.manifestId,
    required this.onRefresh,
    this.embedded = false,
  });
  @override
  ConsumerState<_ManifestDetailPage> createState() => _ManifestDetailPageState();
}

class _ManifestDetailPageState extends ConsumerState<_ManifestDetailPage> {
  Map<String, dynamic>? _manifest;
  bool _loading = true;
  String? _error;

  // Inline attach section state (Phase-3 pattern from external shipments).
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
      final data = await ref.read(internalShipmentsProvider.notifier).getShipment(widget.manifestId);
      if (mounted) setState(() { _manifest = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = '$e'; });
    }
  }

  // ── Attach flow (inline, no nested dialog) ──────────────
  Future<void> _toggleAttach() async {
    setState(() => _attachOpen = !_attachOpen);
    if (_attachOpen && _availableOrders == null) {
      setState(() => _attachLoading = true);
      try {
        final orders = await ref.read(internalShipmentsProvider.notifier).fetchAvailableOrders();
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
      await ref.read(internalShipmentsProvider.notifier).attachOrders(
        widget.manifestId, _selectedOrderIds.toList(),
      );
      widget.onRefresh();
      if (!mounted) return;
      setState(() {
        _selectedOrderIds.clear();
        _availableOrders = null; // force refetch next time
        _attachOpen = false;
      });
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('تم ربط $count طلبية بالمانيفست'),
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

  // ── Handover / per-order edits / per-order return + delivered ──
  Future<void> _showHandoverDialog() async {
    final expected = (_manifest!['cash_expected'] as num?)?.toDouble() ?? 0;
    final ctrl = TextEditingController(text: expected.toStringAsFixed(0));
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) {
        double entered = expected;
        return StatefulBuilder(builder: (dctx, setLocal) {
          final diff = entered - expected;
          final shortfall = diff < -0.5;
          return AlertDialog(
            backgroundColor: AppTheme.darkSurface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('تسليم الكاش', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('متوقع من المندوب: ${expected.toStringAsFixed(0)} د.ل',
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'الكاش المسلَّم (د.ل)',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
                onChanged: (v) => setLocal(() => entered = double.tryParse(v.trim().replaceAll(',', '.')) ?? 0),
              ),
              if (shortfall) ...[
                const SizedBox(height: 10),
                Text('ناقص ${(-diff).toStringAsFixed(0)} د.ل',
                  style: const TextStyle(color: AppTheme.error, fontWeight: FontWeight.w700)),
              ],
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.of(dctx).pop(), child: const Text('إلغاء', style: TextStyle(color: Colors.white54))),
              ElevatedButton(
                onPressed: () => Navigator.of(dctx).pop(entered),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                child: const Text('تأكيد'),
              ),
            ],
          );
        });
      },
    );
    ctrl.dispose();
    if (result == null || !mounted) return;
    try {
      await ref.read(internalShipmentsProvider.notifier).recordHandover(widget.manifestId, result);
      widget.onRefresh();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تم تسجيل تسليم الكاش'),
          backgroundColor: AppTheme.success,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppTheme.error));
      }
    }
  }

  Future<void> _editOrderCash(Map<String, dynamic> order) async {
    final orderId = order['id'] as String;
    final current = (order['cash_collected'] as num?)?.toDouble() ?? 0;
    final ctrl = TextEditingController(text: current.toStringAsFixed(0));
    final result = await showDialog<double>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: AppTheme.darkSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('تعديل المبلغ المحصَّل', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'المحصَّل (د.ل)',
            prefixIcon: Icon(Icons.payments_outlined),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dctx).pop(), child: const Text('إلغاء', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text.trim().replaceAll(',', '.'));
              Navigator.of(dctx).pop(v);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null || !mounted) return;
    try {
      await ref.read(internalShipmentsProvider.notifier).updateOrderCash(widget.manifestId, orderId, result);
      widget.onRefresh();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppTheme.error));
      }
    }
  }

  Future<void> _markOrderDelivered(Map<String, dynamic> order) async {
    final orderId = order['id'] as String;
    // Compute the default cash to seed (sale - deposit if the backend can't
    // derive it locally). Backend does the seed itself; we just show it.
    final expected = _defaultCashFor(order);
    final ctrl = TextEditingController(text: expected.toStringAsFixed(0));
    final result = await showDialog<double?>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: AppTheme.darkSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('تأكيد التسليم', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('المتوقع من الزبون: ${expected.toStringAsFixed(0)} د.ل',
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'المحصَّل عند الباب (د.ل)',
              prefixIcon: Icon(Icons.payments_outlined),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(dctx).pop(), child: const Text('إلغاء', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text.trim().replaceAll(',', '.'));
              Navigator.of(dctx).pop(v);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
            child: const Text('تأكيد التسليم'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null || !mounted) return;
    try {
      await ref.read(internalShipmentsProvider.notifier).markOrderDelivered(
        widget.manifestId, orderId, cashCollected: result,
      );
      widget.onRefresh();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تم تسجيل التسليم'),
          backgroundColor: AppTheme.success,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppTheme.error));
      }
    }
  }

  double _defaultCashFor(Map<String, dynamic> order) {
    final sale = (order['total_sale_price_lyd'] as num?)?.toDouble()
        ?? (order['items_sale_total_lyd'] as num?)?.toDouble() ?? 0;
    final deposit = (order['deposit_amount'] as num?)?.toDouble() ?? 0;
    final diff = sale - deposit;
    return diff < 0 ? 0 : diff;
  }

  Future<void> _returnOrder(String orderId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.darkSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('تأكيد الترجيع', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: const Text(
          'هل تأكد أن هذا الزبون رفض الاستلام؟ سيتم تحويل قطعه للبضاعة الفورية.',
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
            child: const Text('تأكيد الترجيع'),
          ),
        ],
      ),
    );
    if (!context.mounted || confirm != true) return;
    try {
      await ref.read(internalShipmentsProvider.notifier).returnOrder(widget.manifestId, orderId);
      widget.onRefresh();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تم تحويل الطلبية للبضاعة الفورية'),
          backgroundColor: AppTheme.success,
        ));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$e'),
        backgroundColor: AppTheme.error,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = _loading
      ? const Center(child: CircularProgressIndicator())
      : _error != null
        ? Center(child: Text(_error!, style: const TextStyle(color: AppTheme.error)))
        : _buildBody();

    if (widget.embedded) {
      return Padding(padding: const EdgeInsets.all(20), child: body);
    }
    // Full-screen page (mobile route)
    return Scaffold(
      backgroundColor: AppTheme.darkSurface,
      appBar: AppBar(
        backgroundColor: AppTheme.darkSurface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white70),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(_manifest?['delivery_company'] as String? ?? 'المانيفست',
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
      ),
      body: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), child: body),
    );
  }

  Widget _buildBody() {
    final m = _manifest!;
    final status = m['status'] as String? ?? 'pending';
    final statusColor = _statusColor(status);
    final orders = (m['orders'] as List<dynamic>?) ?? [];
    final driverName = (m['driver_name'] as String?)?.trim();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Header row (only in embedded mode — full-screen has an AppBar)
      if (widget.embedded)
        Row(children: [
          const Icon(Icons.local_shipping_rounded, color: AppTheme.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(child: Text(
            m['delivery_company'] as String? ?? '—',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
          )),
          IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.of(context).pop()),
        ]),
      if (widget.embedded) const SizedBox(height: 8),
      // Derived badge + subtitle
      Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: statusColor.withValues(alpha: 0.4)),
          ),
          child: Text(_statusLabel(status),
              style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 8),
        const Expanded(child: Text('حالة "مكتمل" تُحسب تلقائياً من التسليمات',
            style: TextStyle(color: Colors.white38, fontSize: 11))),
      ]),
      if (driverName != null && driverName.isNotEmpty) ...[
        const SizedBox(height: 6),
        Row(children: [
          const Icon(Icons.person_outline, color: Colors.white54, size: 15),
          const SizedBox(width: 6),
          Text('المندوب: $driverName', style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ]),
      ],
      if (status == 'delivered')
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(children: [
            Expanded(child: Text(
              'متوقع: ${((m['cash_expected'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)} د.ل',
              style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
            )),
            if (m['cash_handed_over'] == null)
              ElevatedButton.icon(
                onPressed: _showHandoverDialog,
                icon: const Icon(Icons.payments_outlined, size: 16),
                label: const Text('تسليم الكاش', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
              )
            else
              Builder(builder: (_) {
                final handed = (m['cash_handed_over'] as num).toDouble();
                final expected = (m['cash_expected'] as num?)?.toDouble() ?? 0;
                final diff = handed - expected;
                final shortfall = diff < -0.5;
                final bg = shortfall ? AppTheme.error : AppTheme.success;
                final label = shortfall
                  ? 'تم تسليم ${handed.toStringAsFixed(0)} (ناقص ${(-diff).toStringAsFixed(0)})'
                  : 'تم تسليم ${handed.toStringAsFixed(0)} د.ل';
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: bg.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                  child: Text(label, style: TextStyle(color: bg, fontSize: 11, fontWeight: FontWeight.w600)),
                );
              }),
          ]),
        ),
      const SizedBox(height: 14),
      // Inline attach (Phase-3 pattern)
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
      const Text('الطلبات', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
      const SizedBox(height: 6),
      Expanded(
        child: orders.isEmpty
          ? const Center(child: Text('لا توجد طلبات مرتبطة',
              style: TextStyle(color: Colors.white38, fontSize: 13)))
          : ListView.separated(
              itemCount: orders.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (_, i) => _OrderRow(
                order: orders[i] as Map<String, dynamic>,
                manifestStatus: status,
                onDelivered: () => _markOrderDelivered(orders[i] as Map<String, dynamic>),
                onReturn: () => _returnOrder((orders[i] as Map<String, dynamic>)['id'] as String),
                onEditCash: () => _editOrderCash(orders[i] as Map<String, dynamic>),
              ),
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
        const Text('الطلبات الجاهزة للتوصيل (sorted أو ready_dispatch)، غير مربوطة بعد',
            style: TextStyle(color: Colors.white38, fontSize: 11)),
        const SizedBox(height: 8),
        if (_attachLoading)
          const Padding(padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
        else if ((_availableOrders?.isEmpty ?? true))
          const Padding(padding: EdgeInsets.all(12),
              child: Text('لا توجد طلبات جاهزة',
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
                final name = order['customer_name'] as String? ?? '—';
                final city = order['customer_city'] as String? ?? '';
                final area = order['customer_area'] as String? ?? '';
                final location = [city, area].where((s) => s.isNotEmpty).join(' - ');
                final itemCount = (order['item_count'] as num?)?.toInt() ?? 0;
                final isChecked = _selectedOrderIds.contains(orderId);
                return CheckboxListTile(
                  dense: true,
                  value: isChecked,
                  onChanged: (v) => setState(() => v! ? _selectedOrderIds.add(orderId) : _selectedOrderIds.remove(orderId)),
                  activeColor: AppTheme.primary,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                  title: Text(name,
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
                  subtitle: Text([if (location.isNotEmpty) location, '$itemCount منتج'].join(' · '),
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

// ─── Per-order row inside the manifest detail ─────────────
class _OrderRow extends StatelessWidget {
  final Map<String, dynamic> order;
  final String manifestStatus;
  final VoidCallback onDelivered;
  final VoidCallback onReturn;
  final VoidCallback onEditCash;
  const _OrderRow({
    required this.order,
    required this.manifestStatus,
    required this.onDelivered,
    required this.onReturn,
    required this.onEditCash,
  });

  @override
  Widget build(BuildContext context) {
    final name = order['customer_name'] as String? ?? '—';
    final phone = order['customer_phone'] as String? ?? '';
    final city = order['customer_city'] as String? ?? '';
    final area = order['customer_area'] as String? ?? '';
    final location = [city, area].where((s) => s.isNotEmpty).join(' - ');
    final itemCount = (order['item_count'] as num?)?.toInt() ?? 0;
    final status = order['status'] as String? ?? '';
    final cashCollected = (order['cash_collected'] as num?)?.toDouble() ?? 0;
    final isDelivered = status == 'delivered';
    final isCancelled = status == 'cancelled';
    final canAct = manifestStatus == 'out_for_delivery' && !isDelivered && !isCancelled;

    Color chipBg;
    Color chipFg;
    String chipLabel;
    if (isDelivered) {
      chipBg = AppTheme.success; chipFg = AppTheme.success; chipLabel = 'مكتمل';
    } else if (isCancelled) {
      chipBg = AppTheme.error; chipFg = AppTheme.error; chipLabel = 'مُرجَع';
    } else {
      chipBg = AppTheme.accent; chipFg = AppTheme.accent; chipLabel = 'بانتظار التسليم';
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: chipBg.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(
              [if (phone.isNotEmpty) phone, if (location.isNotEmpty) location, '$itemCount منتج'].join(' · '),
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: chipBg.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
            child: Text(chipLabel, style: TextStyle(color: chipFg, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ]),
        if (isDelivered) ...[
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.payments_outlined, size: 13, color: AppTheme.success),
            const SizedBox(width: 4),
            Text('قبض: ${cashCollected.toStringAsFixed(0)} د.ل',
                style: const TextStyle(color: AppTheme.success, fontSize: 11, fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 13, color: Colors.white54),
              tooltip: 'تعديل المحصَّل',
              onPressed: onEditCash,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            ),
          ]),
        ],
        if (canAct) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: ElevatedButton.icon(
              onPressed: onDelivered,
              icon: const Icon(Icons.check_circle_outline, size: 16),
              label: const Text('تم التسليم', style: TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.success,
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
            )),
            const SizedBox(width: 6),
            OutlinedButton.icon(
              onPressed: onReturn,
              icon: const Icon(Icons.reply_rounded, size: 15, color: AppTheme.error),
              label: const Text('راجع → فوري',
                  style: TextStyle(color: AppTheme.error, fontSize: 12)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppTheme.error.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
              ),
            ),
          ]),
        ],
      ]),
    );
  }
}
