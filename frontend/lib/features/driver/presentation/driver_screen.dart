import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:estore_app/app/theme.dart';
import 'package:estore_app/core/providers.dart';

/// Driver's home surface. Loads GET /internal-shipments/mine (backend
/// filters by users.full_name for role driver) and shows one card per
/// open manifest. Tapping a manifest opens a full-screen stop list.
///
/// Layout is mobile-first — a single centered column ≤ 520 px. On desktop
/// the same layout is used (drivers rarely use desktop; consistency wins).
class DriverScreen extends ConsumerWidget {
  const DriverScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(driverManifestsProvider);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: state.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.cloud_off_rounded, color: AppTheme.error, size: 48),
                const SizedBox(height: 12),
                Text('$e', style: const TextStyle(color: Colors.white54), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => ref.invalidate(driverManifestsProvider),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('إعادة المحاولة'),
                ),
              ]),
            ),
          ),
          data: (manifests) {
            if (manifests.isEmpty) {
              return RefreshIndicator(
                color: AppTheme.primary,
                onRefresh: () async => ref.invalidate(driverManifestsProvider),
                child: ListView(children: const [
                  SizedBox(height: 120),
                  Icon(Icons.local_shipping_rounded, color: Colors.white12, size: 84),
                  SizedBox(height: 16),
                  Center(child: Text('لا توجد شحنات مفتوحة',
                      style: TextStyle(color: Colors.white54, fontSize: 16))),
                  SizedBox(height: 6),
                  Center(child: Text('اسحب للأسفل للتحديث',
                      style: TextStyle(color: Colors.white38, fontSize: 12))),
                ]),
              );
            }
            return RefreshIndicator(
              color: AppTheme.primary,
              onRefresh: () async => ref.invalidate(driverManifestsProvider),
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: manifests.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) => _ManifestSummaryCard(manifest: manifests[i]),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─── Manifest summary card (main screen) ──────────────────
class _ManifestSummaryCard extends StatelessWidget {
  final Map<String, dynamic> manifest;
  const _ManifestSummaryCard({required this.manifest});

  @override
  Widget build(BuildContext context) {
    final company = manifest['delivery_company'] as String? ?? '—';
    final createdAt = (manifest['created_at'] as String? ?? '').length >= 10
        ? (manifest['created_at'] as String).substring(0, 10)
        : (manifest['created_at'] as String? ?? '');
    final orders = (manifest['orders'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final pendingStops = orders.where((o) => (o['status'] as String? ?? '') != 'delivered'
        && (o['status'] as String? ?? '') != 'cancelled').length;
    final expectedTotal = orders.fold<double>(
      0.0,
      (sum, o) {
        final s = o['status'] as String? ?? '';
        if (s == 'cancelled') return sum;
        return sum + ((o['expected_cash'] as num?)?.toDouble() ?? 0);
      },
    );
    final allDone = orders.isNotEmpty && pendingStops == 0;

    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _StopListPage(manifestId: manifest['id'] as String, company: company),
      )),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.darkSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: (allDone ? AppTheme.success : AppTheme.primary).withValues(alpha: 0.35)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (allDone ? AppTheme.success : AppTheme.primary).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(allDone ? Icons.check_circle_rounded : Icons.local_shipping_rounded,
                  color: allDone ? AppTheme.success : AppTheme.primary, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(company, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('${orders.length} نقطة · $createdAt',
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ])),
            const Icon(Icons.chevron_right, color: Colors.white38),
          ]),
          const SizedBox(height: 14),
          const Divider(height: 1, color: AppTheme.darkBorder),
          const SizedBox(height: 12),
          if (allDone)
            const Row(children: [
              Icon(Icons.done_all_rounded, color: AppTheme.success, size: 18),
              SizedBox(width: 8),
              Expanded(child: Text('مكتمل — سلّم الكاش للمكتب',
                  style: TextStyle(color: AppTheme.success, fontSize: 13, fontWeight: FontWeight.w700))),
            ])
          else
            Row(children: [
              const Icon(Icons.payments_outlined, color: Colors.white54, size: 16),
              const SizedBox(width: 6),
              Expanded(child: Text('متوقع تحصيله: ${expectedTotal.toStringAsFixed(0)} د.ل',
                  style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600))),
              Text('$pendingStops متبقّي',
                  style: const TextStyle(color: AppTheme.accent, fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
        ]),
      ),
    );
  }
}

// ─── Stop list (per-manifest full-screen page) ────────────
class _StopListPage extends ConsumerStatefulWidget {
  final String manifestId;
  final String company;
  const _StopListPage({required this.manifestId, required this.company});
  @override
  ConsumerState<_StopListPage> createState() => _StopListPageState();
}

class _StopListPageState extends ConsumerState<_StopListPage> {
  bool _busyOrderId = false;

  Map<String, dynamic>? _findManifest() {
    final data = ref.read(driverManifestsProvider).valueOrNull;
    if (data == null) return null;
    return data.firstWhere(
      (m) => m['id'] == widget.manifestId,
      orElse: () => <String, dynamic>{},
    );
  }

  Future<void> _confirmDelivered(Map<String, dynamic> order) async {
    final expected = (order['expected_cash'] as num?)?.toDouble() ?? 0;
    final ctrl = TextEditingController(text: expected.toStringAsFixed(0));
    final entered = await showModalBottomSheet<double?>(
      context: context,
      backgroundColor: AppTheme.darkSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (dctx) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: 20 + MediaQuery.of(dctx).viewInsets.bottom,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
          ),
          Text('تأكيد التسليم — ${order['customer_name'] ?? '—'}',
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('المتوقع من الزبونة: ${expected.toStringAsFixed(0)} د.ل',
              style: const TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 16),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              labelText: 'المحصَّل عند الباب (د.ل)',
              prefixIcon: Icon(Icons.payments_outlined),
            ),
          ),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: TextButton(
              onPressed: () => Navigator.of(dctx).pop(),
              child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
            )),
            const SizedBox(width: 10),
            Expanded(child: SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: () {
                  final v = double.tryParse(ctrl.text.trim().replaceAll(',', '.'));
                  Navigator.of(dctx).pop(v);
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
                child: const Text('تأكيد التسليم', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            )),
          ]),
        ]),
      ),
    );
    ctrl.dispose();
    if (entered == null || !mounted) return;
    await _runOrderAction(() => ref.read(internalShipmentsProvider.notifier).markOrderDelivered(
      widget.manifestId,
      order['order_id'] as String,
      cashCollected: entered,
    ), successMsg: 'تم تسجيل التسليم');
  }

  Future<void> _confirmReturn(Map<String, dynamic> order) async {
    final confirm = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppTheme.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (dctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
          ),
          const Text('الزبونة رفضت؟',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('سيتم إرجاع طلبية ${order['customer_name'] ?? '—'} وتحويل قطعها للبضاعة الفورية.',
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: TextButton(
              onPressed: () => Navigator.of(dctx).pop(false),
              child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
            )),
            const SizedBox(width: 10),
            Expanded(child: SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: () => Navigator.of(dctx).pop(true),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
                child: const Text('تأكيد الترجيع', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            )),
          ]),
        ]),
      ),
    );
    if (confirm != true || !mounted) return;
    await _runOrderAction(() => ref.read(internalShipmentsProvider.notifier).returnOrder(
      widget.manifestId,
      order['order_id'] as String,
    ), successMsg: 'تم إرجاع الطلبية');
  }

  Future<void> _runOrderAction(Future<void> Function() action, {required String successMsg}) async {
    if (_busyOrderId) return;
    setState(() => _busyOrderId = true);
    try {
      await action();
      ref.invalidate(driverManifestsProvider);
      // Wait for the refetch so the UI reflects the new state before we finish.
      await ref.read(driverManifestsProvider.future);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(successMsg),
          backgroundColor: AppTheme.success,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$e'),
          backgroundColor: AppTheme.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _busyOrderId = false);
    }
  }

  Future<void> _openTel(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _openMap(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(driverManifestsProvider);

    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        backgroundColor: AppTheme.darkSurface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(widget.company,
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e', style: const TextStyle(color: AppTheme.error))),
        data: (_) {
          final manifest = _findManifest();
          if (manifest == null || manifest.isEmpty) {
            return const Center(child: Text('لم يتم العثور على المانيفست',
                style: TextStyle(color: Colors.white54)));
          }
          final ordersRaw = (manifest['orders'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
          // Pending stops first, delivered/returned collapse to the bottom.
          final pending = ordersRaw.where((o) {
            final s = o['status'] as String? ?? '';
            return s != 'delivered' && s != 'cancelled';
          }).toList();
          final done = ordersRaw.where((o) {
            final s = o['status'] as String? ?? '';
            return s == 'delivered' || s == 'cancelled';
          }).toList();
          final allDone = pending.isEmpty && ordersRaw.isNotEmpty;

          return RefreshIndicator(
            color: AppTheme.primary,
            onRefresh: () async => ref.invalidate(driverManifestsProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                if (allDone)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.success.withValues(alpha: 0.4)),
                    ),
                    child: const Row(children: [
                      Icon(Icons.done_all_rounded, color: AppTheme.success, size: 22),
                      SizedBox(width: 10),
                      Expanded(child: Text('مكتمل — سلّم الكاش للمكتب',
                          style: TextStyle(color: AppTheme.success, fontSize: 14, fontWeight: FontWeight.w700))),
                    ]),
                  ),
                for (final o in pending)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _StopCard(
                      order: o,
                      busy: _busyOrderId,
                      onCall: _openTel,
                      onMap: _openMap,
                      onDelivered: () => _confirmDelivered(o),
                      onReturn: () => _confirmReturn(o),
                    ),
                  ),
                if (done.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.only(top: 8, bottom: 8),
                    child: Text('تم إنجازها',
                        style: TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                  for (final o in done)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _DoneStrip(order: o),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Full stop card ──────────────────────────────────────
class _StopCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final bool busy;
  final Future<void> Function(String phone) onCall;
  final Future<void> Function(String url) onMap;
  final VoidCallback onDelivered;
  final VoidCallback onReturn;
  const _StopCard({
    required this.order,
    required this.busy,
    required this.onCall,
    required this.onMap,
    required this.onDelivered,
    required this.onReturn,
  });

  @override
  Widget build(BuildContext context) {
    final name = order['customer_name'] as String? ?? '—';
    final phone = order['customer_phone'] as String? ?? '';
    final phone2 = order['customer_phone2'] as String? ?? '';
    final city = order['customer_city'] as String? ?? '';
    final area = order['customer_area'] as String? ?? '';
    final street = order['customer_street'] as String? ?? '';
    final address = order['customer_address'] as String? ?? '';
    final locationUrl = order['customer_location_url'] as String? ?? '';
    final expected = (order['expected_cash'] as num?)?.toDouble() ?? 0;
    final items = (order['items'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final addressLines = [
      [city, area].where((s) => s.isNotEmpty).join(' - '),
      street,
      address,
    ].where((s) => s.trim().isNotEmpty).toList();

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Header — customer name
        Text(name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        // Phone — tap to call
        if (phone.isNotEmpty)
          InkWell(
            onTap: () => onCall(phone),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                const Icon(Icons.phone_rounded, color: AppTheme.primary, size: 18),
                const SizedBox(width: 8),
                Text(phone,
                    style: const TextStyle(color: AppTheme.primary, fontSize: 14, fontWeight: FontWeight.w600)),
                if (phone2.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.phone_outlined, color: Colors.white54, size: 16),
                  const SizedBox(width: 4),
                  Text(phone2, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ]),
            ),
          ),
        if (addressLines.isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.location_on_outlined, color: Colors.white54, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: addressLines.map((l) => Text(l,
                  style: const TextStyle(color: Colors.white70, fontSize: 13))).toList(),
            )),
          ]),
        ],
        if (locationUrl.isNotEmpty) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => onMap(locationUrl),
              icon: const Icon(Icons.map_rounded, size: 16),
              label: const Text('افتح الموقع', style: TextStyle(fontSize: 13)),
              style: TextButton.styleFrom(foregroundColor: AppTheme.secondary),
            ),
          ),
        ],
        const SizedBox(height: 8),
        const Divider(height: 1, color: AppTheme.darkBorder),
        const SizedBox(height: 8),
        // Item list — name × qty only (driver never sees price/cost)
        for (final it in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              const Icon(Icons.check_box_outline_blank, color: Colors.white38, size: 14),
              const SizedBox(width: 8),
              Expanded(child: Text('${it['product_name'] ?? '—'}  ×${it['quantity'] ?? 1}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13))),
            ]),
          ),
        const SizedBox(height: 12),
        // Amount to collect — big
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: AppTheme.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
          ),
          child: Row(children: [
            const Icon(Icons.payments_rounded, color: AppTheme.accent, size: 22),
            const SizedBox(width: 10),
            const Text('يُحصَّل: ',
                style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600)),
            Expanded(child: Text('${expected.toStringAsFixed(0)} د.ل',
                textAlign: TextAlign.end,
                style: const TextStyle(color: AppTheme.accent, fontSize: 22, fontWeight: FontWeight.w800))),
          ]),
        ),
        const SizedBox(height: 12),
        // Two big buttons — deliver / return
        Row(children: [
          Expanded(child: SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: busy ? null : onDelivered,
              icon: const Icon(Icons.check_circle_rounded, size: 20),
              label: const Text('تم التسليم',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
            ),
          )),
          const SizedBox(width: 8),
          Expanded(child: SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed: busy ? null : onReturn,
              icon: const Icon(Icons.cancel_outlined, size: 20, color: AppTheme.error),
              label: const Text('الزبونة رفضت',
                  style: TextStyle(color: AppTheme.error, fontSize: 14, fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppTheme.error, width: 1.5),
              ),
            ),
          )),
        ]),
      ]),
    );
  }
}

// ─── Done strip (collapsed after delivered/returned) ──────
class _DoneStrip extends StatelessWidget {
  final Map<String, dynamic> order;
  const _DoneStrip({required this.order});

  @override
  Widget build(BuildContext context) {
    final name = order['customer_name'] as String? ?? '—';
    final status = order['status'] as String? ?? '';
    final cash = (order['cash_collected'] as num?)?.toDouble() ?? 0;
    final isDelivered = status == 'delivered';
    final color = isDelivered ? AppTheme.success : AppTheme.error;
    final label = isDelivered
        ? 'مسلَّمة — ${cash.toStringAsFixed(0)} د.ل'
        : 'مُرجَعة';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border(right: BorderSide(color: color, width: 4)),
      ),
      child: Row(children: [
        Icon(isDelivered ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(name,
            style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600))),
        Text(label,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}
