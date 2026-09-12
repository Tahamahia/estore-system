import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:estore_app/app/theme.dart';
import 'package:estore_app/core/api_client.dart';
import 'package:estore_app/core/providers.dart';
import 'package:estore_app/core/utils/dialog_utils.dart';

class SettlementsScreen extends ConsumerStatefulWidget {
  const SettlementsScreen({super.key});

  @override
  ConsumerState<SettlementsScreen> createState() => _SettlementsScreenState();
}

class _SettlementsScreenState extends ConsumerState<SettlementsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(settlementsProvider.notifier).fetchSettlements());
  }

  void _showNewSettlement() {
    final flow = _NewSettlementFlow(
      onCreated: () => ref.read(settlementsProvider.notifier).fetchSettlements(),
    );
    if (isMobile(context)) {
      Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => flow));
    } else {
      showDialog(context: context, builder: (_) => flow);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(settlementsProvider);
    final mobile = isMobile(context);

    return Stack(children: [
      Padding(
      padding: EdgeInsets.fromLTRB(mobile ? 12 : 24, mobile ? 12 : 24, mobile ? 12 : 24, mobile ? 80 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('التسويات المالية', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white)),
            const Spacer(),
            if (!mobile) ...[
              ElevatedButton.icon(
                onPressed: _showNewSettlement,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('تسوية جديدة'),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
              ),
              const SizedBox(width: 8),
            ],
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white54),
              tooltip: 'تحديث',
              onPressed: () => ref.read(settlementsProvider.notifier).fetchSettlements(),
            ),
          ]),
          const SizedBox(height: 8),
          const Text(
            'مجموعات الطلبات المسوّاة — يُحسب المكسب الصافي بالدولار بناءً على سعر الصرف الفعلي وقت الشراء.',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: state.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: AppTheme.error, size: 48),
                  const SizedBox(height: 12),
                  const Text('فشل تحميل التسويات', style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () => ref.read(settlementsProvider.notifier).fetchSettlements(),
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              )),
              data: (settlements) {
                if (settlements.isEmpty) {
                  return Center(child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: AppTheme.darkCard,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.account_balance_wallet_outlined, color: Colors.white38, size: 48),
                      ),
                      const SizedBox(height: 20),
                      const Text('لا توجد تسويات بعد', style: TextStyle(color: Colors.white54, fontSize: 16)),
                      const SizedBox(height: 8),
                      const Text(
                        'حدّد طلبات من شاشة الطلبات وأنشئ تسوية مالية.',
                        style: TextStyle(color: Colors.white38, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ));
                }

                return ListView.separated(
                  itemCount: settlements.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 16),
                  itemBuilder: (_, i) => _SettlementCard(settlement: settlements[i]),
                );
              },
            ),
          ),
        ],
      ),
      ),
      if (mobile)
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton.extended(
            onPressed: _showNewSettlement,
            backgroundColor: AppTheme.success,
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text('تسوية جديدة', style: TextStyle(color: Colors.white)),
          ),
        ),
    ]);
  }
}

// ─── Settlement Card ───────────────────────────────────────
class _SettlementCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> settlement;
  const _SettlementCard({required this.settlement});

  @override
  ConsumerState<_SettlementCard> createState() => _SettlementCardState();
}

class _SettlementCardState extends ConsumerState<_SettlementCard> {
  String _formatDate(String raw) {
    if (raw.length < 10) return raw.isEmpty ? '—' : raw;
    final parts = raw.substring(0, 10).split('-');
    if (parts.length < 3) return raw.substring(0, 10);
    return '${parts[2]}/${parts[1]}/${parts[0]}';
  }

  void _showDetail(BuildContext context) {
    final id = widget.settlement['id'] as String;
    showDialog(
      context: context,
      builder: (_) => _SettlementDetailDialog(settlementId: id),
    );
  }

  void _showEdit(BuildContext context) {
    final s = widget.settlement;
    final id = s['id'] as String;
    final name = s['name'] as String? ?? '';
    final rate = (s['exchange_rate'] as num?)?.toDouble() ?? 0;
    showDialog(
      context: context,
      builder: (_) => _EditSettlementDialog(
        settlementId: id,
        initialName: name,
        initialRate: rate,
        onSaved: (newName, newRate) async {
          await ref.read(settlementsProvider.notifier).updateSettlement(
            id,
            name: newName.isNotEmpty ? newName : null,
            exchangeRate: newRate > 0 ? newRate : null,
          );
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('تم تحديث التسوية'),
              backgroundColor: AppTheme.success,
            ));
          }
        },
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final id = widget.settlement['id'] as String;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.darkSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('حذف التسوية', style: TextStyle(color: Colors.white)),
        content: const Text(
          'سيتم فك ربط جميع الطلبيات وإلغاء شطب البضاعة الفورية المرتبطة. هذا الإجراء لا يمكن التراجع عنه.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(settlementsProvider.notifier).deleteSettlement(id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تم حذف التسوية'),
        backgroundColor: AppTheme.success,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settlement;
    final name = s['name'] as String? ?? '—';
    final exchangeRate = (s['exchange_rate'] as num?)?.toDouble() ?? 0;
    final createdAt = s['created_at'] as String? ?? '';
    final totalLyd = (s['total_lyd_collected'] as num?)?.toDouble() ?? 0;
    final totalUsdCost = (s['total_usd_cost'] as num?)?.toDouble() ?? 0;
    final writeOffUsd = (s['total_write_off_usd'] as num?)?.toDouble() ?? 0;
    final writeOffCount = (s['write_off_item_count'] as num?)?.toInt() ?? 0;
    final orderCount = (s['order_count'] as num?)?.toInt() ?? 0;
    final cashShortfall = (s['cash_shortfall'] as num?)?.toDouble() ?? 0;

    final boughtUsd = exchangeRate > 0 ? totalLyd / exchangeRate : 0.0;
    final netProfit = boughtUsd - totalUsdCost - writeOffUsd;
    final isProfit = netProfit >= 0;

    return GestureDetector(
      onTap: () => _showDetail(context),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.darkSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.darkBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.account_balance_wallet_outlined, color: AppTheme.success, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
              const SizedBox(height: 2),
              Row(children: [
                Text(_formatDate(createdAt), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                  child: Text('$orderCount طلب', style: const TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ]),
            ])),
            // Exchange rate badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.darkCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.darkBorder),
              ),
              child: Column(children: [
                const Text('سعر الصرف', style: TextStyle(color: Colors.white38, fontSize: 10)),
                Text('${exchangeRate.toStringAsFixed(2)} د.ل', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
              ]),
            ),
            const SizedBox(width: 4),
            // Edit button
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              color: Colors.white54,
              tooltip: 'تعديل',
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(),
              onPressed: () => _showEdit(context),
            ),
            // Delete button
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              color: AppTheme.error,
              tooltip: 'حذف',
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(),
              onPressed: () => _confirmDelete(context),
            ),
          ]),
          const SizedBox(height: 20),

          // Financial grid
          Row(children: [
            _FinStat(
              label: 'إجمالي المحصل',
              value: '${totalLyd.toStringAsFixed(0)} د.ل',
              icon: Icons.payments_outlined,
              color: AppTheme.secondary,
            ),
            const SizedBox(width: 12),
            _FinStat(
              label: 'إجمالي التكلفة',
              value: '\$${totalUsdCost.toStringAsFixed(2)}',
              icon: Icons.shopping_cart_outlined,
              color: AppTheme.warning,
            ),
            const SizedBox(width: 12),
            _FinStat(
              label: 'الدولار المشترى',
              value: '\$${boughtUsd.toStringAsFixed(2)}',
              icon: Icons.currency_exchange_outlined,
              color: AppTheme.primary,
            ),
          ]),
          if (writeOffCount > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.error.withValues(alpha: 0.2)),
              ),
              child: Row(children: [
                const Icon(Icons.inventory_2_outlined, color: AppTheme.error, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  'خسائر بضاعة فورية لم تُبع ($writeOffCount منتج)',
                  style: const TextStyle(color: AppTheme.error, fontSize: 12),
                )),
                Text(
                  '-\$${writeOffUsd.toStringAsFixed(2)}',
                  style: const TextStyle(color: AppTheme.error, fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 14),

          // Net profit — prominent
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: (isProfit ? AppTheme.success : AppTheme.error).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: (isProfit ? AppTheme.success : AppTheme.error).withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              Icon(
                isProfit ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                color: isProfit ? AppTheme.success : AppTheme.error,
                size: 28,
              ),
              const SizedBox(width: 14),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('المكسب الصافي (USD)', style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 2),
                Text(
                  '${isProfit ? '+' : ''}\$${netProfit.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: isProfit ? AppTheme.success : AppTheme.error,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ]),
              const Spacer(),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                const Text('هامش الربح', style: TextStyle(color: Colors.white38, fontSize: 11)),
                const SizedBox(height: 2),
                Text(
                  boughtUsd > 0
                    ? '${(netProfit / boughtUsd * 100).toStringAsFixed(1)}%'
                    : '—',
                  style: TextStyle(
                    color: isProfit ? AppTheme.success : AppTheme.error,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ]),
            ]),
          ),
          if (cashShortfall > 0.5) ...[
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.warning_amber_rounded, color: AppTheme.error, size: 16),
              const SizedBox(width: 8),
              Text('نقص في التحصيل: ${cashShortfall.toStringAsFixed(0)} د.ل',
                  style: const TextStyle(color: AppTheme.error, fontSize: 13, fontWeight: FontWeight.w700)),
            ]),
          ],
        ]),
      ),
    );
  }
}

// ─── Settlement Detail Dialog ──────────────────────────────
class _SettlementDetailDialog extends ConsumerStatefulWidget {
  final String settlementId;
  const _SettlementDetailDialog({required this.settlementId});

  @override
  ConsumerState<_SettlementDetailDialog> createState() => _SettlementDetailDialogState();
}

class _SettlementDetailDialogState extends ConsumerState<_SettlementDetailDialog> {
  late Future<Map<String, dynamic>> _detailFuture;

  @override
  void initState() {
    super.initState();
    _detailFuture = ref.read(settlementsProvider.notifier).fetchSettlementDetail(widget.settlementId);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: isMobile(context) ? 8 : 40, vertical: 24),
      backgroundColor: AppTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: dialogMaxWidth(context, desktopMax: 520), maxHeight: dialogMaxHeight(context)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Header
            Row(children: [
              const Icon(Icons.receipt_long_outlined, color: AppTheme.success, size: 22),
              const SizedBox(width: 10),
              const Expanded(child: Text('تفاصيل التسوية', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white))),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white38),
                onPressed: () => Navigator.of(context).pop(),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ]),
            const SizedBox(height: 16),
            Expanded(
              child: FutureBuilder<Map<String, dynamic>>(
                future: _detailFuture,
                builder: (ctx, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return Center(child: Text('فشل تحميل التفاصيل', style: const TextStyle(color: AppTheme.error)));
                  }
                  final detail = snap.data!;
                  final orders = List<Map<String, dynamic>>.from(detail['orders'] as List? ?? []);

                  if (orders.isEmpty) {
                    return const Center(child: Text('لا توجد طلبيات في هذه التسوية', style: TextStyle(color: Colors.white54)));
                  }

                  return ListView.separated(
                    itemCount: orders.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.darkBorder),
                    itemBuilder: (_, i) {
                      final o = orders[i];
                      final rawId = o['id'] as String? ?? '';
                      final shortId = '#${rawId.length >= 8 ? rawId.substring(0, 8).toUpperCase() : rawId.toUpperCase()}';
                      final customerName = o['customer_name'] as String? ?? '—';
                      final itemCount = (o['item_count'] as num?)?.toInt() ?? 0;
                      final totalLyd = (o['total_lyd'] as num?)?.toDouble() ?? 0;
                      final orderShortfall = (o['cash_shortfall'] as num?)?.toDouble() ?? 0;
                      final short = orderShortfall > 0.5;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: (short ? AppTheme.error : AppTheme.success).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              short ? Icons.warning_amber_rounded : Icons.receipt_outlined,
                              color: short ? AppTheme.error : AppTheme.success,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(shortId, style: const TextStyle(color: AppTheme.secondary, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                            const SizedBox(height: 2),
                            Text(customerName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                            if (short) ...[
                              const SizedBox(height: 2),
                              Text('نقص ${orderShortfall.toStringAsFixed(0)} د.ل',
                                  style: const TextStyle(color: AppTheme.error, fontSize: 11, fontWeight: FontWeight.w700)),
                            ],
                          ])),
                          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text('$itemCount منتج', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                            const SizedBox(height: 2),
                            Text('${totalLyd.toStringAsFixed(0)} د.ل', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                          ]),
                        ]),
                      );
                    },
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─── Edit Settlement Dialog ────────────────────────────────
class _EditSettlementDialog extends StatefulWidget {
  final String settlementId;
  final String initialName;
  final double initialRate;
  final Future<void> Function(String name, double rate) onSaved;
  const _EditSettlementDialog({
    required this.settlementId,
    required this.initialName,
    required this.initialRate,
    required this.onSaved,
  });

  @override
  State<_EditSettlementDialog> createState() => _EditSettlementDialogState();
}

class _EditSettlementDialogState extends State<_EditSettlementDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _rateCtrl;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
    _rateCtrl = TextEditingController(text: widget.initialRate > 0 ? widget.initialRate.toStringAsFixed(2) : '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _rateCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: isMobile(context) ? 8 : 40, vertical: 24),
      backgroundColor: AppTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: dialogMaxWidth(context, desktopMax: 400), maxHeight: dialogMaxHeight(context, cap: 400)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Icon(Icons.edit_outlined, color: AppTheme.primary, size: 20),
              const SizedBox(width: 10),
              const Expanded(child: Text('تعديل التسوية', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white))),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white38),
                onPressed: () => Navigator.of(context).pop(),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ]),
            const SizedBox(height: 20),
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: AppTheme.error.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                child: Text(_error!, style: const TextStyle(color: AppTheme.error, fontSize: 13)),
              ),
            ],
            TextField(
              controller: _nameCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'اسم الدفعة',
                prefixIcon: Icon(Icons.label_outline),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _rateCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'سعر الصرف (د.ل / \$)',
                prefixIcon: Icon(Icons.currency_exchange_outlined),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(height: 46, child: ElevatedButton.icon(
              onPressed: _loading ? null : () async {
                final name = _nameCtrl.text.trim();
                final rate = double.tryParse(_rateCtrl.text.trim());
                if (rate != null && rate <= 0) {
                  setState(() => _error = 'سعر الصرف يجب أن يكون رقماً موجباً');
                  return;
                }
                setState(() { _loading = true; _error = null; });
                final nav = Navigator.of(context);
                try {
                  await widget.onSaved(name, rate ?? 0);
                  if (mounted) nav.pop();
                } catch (e) {
                  if (mounted) setState(() { _loading = false; _error = e.toString(); });
                }
              },
              icon: _loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check, size: 20),
              label: Text(_loading ? 'جاري الحفظ...' : 'حفظ التغييرات'),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            )),
          ]),
        ),
      ),
    );
  }
}

// ─── New Settlement flow — full-screen on mobile, dialog on desktop ───
// Loads GET /orders?status=delivered&unsettled=true&limit=200 and lists them
// pre-checked with a select-all toggle and a live footer. Name is pre-filled
// with "تسوية <شهر بالعربي> <سنة>" so a common case is one-tap ready.
class _NewSettlementFlow extends ConsumerStatefulWidget {
  final VoidCallback onCreated;
  const _NewSettlementFlow({required this.onCreated});
  @override
  ConsumerState<_NewSettlementFlow> createState() => _NewSettlementFlowState();
}

class _NewSettlementFlowState extends ConsumerState<_NewSettlementFlow> {
  final _nameCtrl = TextEditingController();
  final _rateCtrl = TextEditingController();
  bool _writeOff = false;
  bool _submitting = false;
  String? _error;
  bool _loadingOrders = true;
  List<Map<String, dynamic>> _eligibleOrders = [];
  final Set<String> _selectedIds = {};
  late Future<int> _inStockCountFuture;

  static const _monthsAr = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _nameCtrl.text = 'تسوية ${_monthsAr[now.month - 1]} ${now.year}';
    _inStockCountFuture = _fetchInStockCount();
    _loadEligible();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _rateCtrl.dispose();
    super.dispose();
  }

  Future<int> _fetchInStockCount() async {
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.get('/inventory/in-stock', queryParameters: {'limit': 1, 'page': 1});
      return ((res.data as Map<String, dynamic>)['total'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _loadEligible() async {
    setState(() { _loadingOrders = true; _error = null; });
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.get('/orders', queryParameters: {
        'status': 'delivered',
        'unsettled': 'true',
        'limit': 200,
      });
      final list = List<Map<String, dynamic>>.from(
        (res.data as Map<String, dynamic>)['data'] ?? const [],
      );
      if (!mounted) return;
      setState(() {
        _eligibleOrders = list;
        _selectedIds
          ..clear()
          ..addAll(list.map((o) => o['id'] as String));
        _loadingOrders = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loadingOrders = false; });
    }
  }

  double _saleTotal(Map<String, dynamic> o) {
    final items = (o['items_sale_total_lyd'] as num?)?.toDouble() ?? 0;
    if (items > 0) return items;
    return (o['total_sale_price_lyd'] as num?)?.toDouble() ?? 0;
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final rate = double.tryParse(_rateCtrl.text.trim());
    if (name.isEmpty) { setState(() => _error = 'اسم الدفعة مطلوب'); return; }
    if (rate == null || rate <= 0) { setState(() => _error = 'سعر الصرف يجب أن يكون رقماً موجباً'); return; }
    if (_selectedIds.isEmpty) { setState(() => _error = 'اختر طلبيات على الأقل'); return; }
    setState(() { _submitting = true; _error = null; });
    try {
      await ref.read(settlementsProvider.notifier).createSettlement(
        name: name,
        exchangeRate: rate,
        orderIds: _selectedIds.toList(),
        writeOff: _writeOff,
      );
      widget.onCreated();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() { _submitting = false; _error = '$e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody();
    if (isMobile(context)) {
      return Scaffold(
        backgroundColor: AppTheme.darkSurface,
        appBar: AppBar(
          backgroundColor: AppTheme.darkSurface,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white70),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text('تسوية جديدة',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        body: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), child: body),
      );
    }
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      backgroundColor: AppTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogMaxWidth(context, desktopMax: 560),
          maxHeight: dialogMaxHeight(context, cap: 760),
        ),
        child: Padding(padding: const EdgeInsets.all(20), child: body),
      ),
    );
  }

  Widget _buildBody() {
    final totalSelected = _eligibleOrders
        .where((o) => _selectedIds.contains(o['id']))
        .fold<double>(0, (sum, o) => sum + _saleTotal(o));
    final allSelected = _eligibleOrders.isNotEmpty && _selectedIds.length == _eligibleOrders.length;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _nameCtrl,
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(
          labelText: 'اسم الدفعة *',
          prefixIcon: Icon(Icons.label_outline),
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _rateCtrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(
          labelText: 'سعر الصرف (د.ل / \$) *',
          hintText: 'مثال: 5.85',
          hintStyle: TextStyle(color: Colors.white24),
          prefixIcon: Icon(Icons.currency_exchange_outlined),
        ),
      ),
      const SizedBox(height: 10),
      // Write-off toggle + live in-stock hint
      Container(
        decoration: BoxDecoration(
          color: AppTheme.darkCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _writeOff ? AppTheme.warning.withValues(alpha: 0.4) : AppTheme.darkBorder),
        ),
        child: CheckboxListTile(
          value: _writeOff,
          onChanged: (v) => setState(() => _writeOff = v ?? false),
          activeColor: AppTheme.warning,
          title: const Text('شطب البضاعة الفورية غير المباعة في هذه التسوية',
              style: TextStyle(color: Colors.white, fontSize: 13)),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          dense: true,
        ),
      ),
      const SizedBox(height: 6),
      FutureBuilder<int>(
        future: _inStockCountFuture,
        builder: (ctx, snap) {
          final count = snap.data ?? 0;
          if (_writeOff) {
            return Text('سيتم شطب $count منتج كخسارة',
                style: const TextStyle(color: AppTheme.warning, fontSize: 12));
          }
          return const Text('لن يتم شطب أي بضاعة فورية',
              style: TextStyle(color: Colors.white38, fontSize: 12));
        },
      ),
      const SizedBox(height: 14),
      Row(children: [
        const Text('الطلبات المسلَّمة غير المسوّاة',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
        const Spacer(),
        if (_eligibleOrders.isNotEmpty)
          TextButton.icon(
            onPressed: () => setState(() {
              if (allSelected) {
                _selectedIds.clear();
              } else {
                _selectedIds
                  ..clear()
                  ..addAll(_eligibleOrders.map((o) => o['id'] as String));
              }
            }),
            icon: Icon(allSelected ? Icons.deselect : Icons.select_all, size: 16),
            label: Text(allSelected ? 'إلغاء الاختيار' : 'اختيار الكل',
                style: const TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
          ),
      ]),
      const SizedBox(height: 6),
      Expanded(
        child: _loadingOrders
            ? const Center(child: CircularProgressIndicator())
            : _eligibleOrders.isEmpty
                ? const Center(
                    child: Text('لا توجد طلبيات مسلَّمة بانتظار التسوية',
                        style: TextStyle(color: Colors.white38, fontSize: 13)),
                  )
                : Container(
                    decoration: BoxDecoration(
                      color: AppTheme.darkCard.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.darkBorder),
                    ),
                    child: ListView.builder(
                      itemCount: _eligibleOrders.length,
                      itemBuilder: (_, i) {
                        final o = _eligibleOrders[i];
                        final id = o['id'] as String;
                        final checked = _selectedIds.contains(id);
                        final customer = o['customer_name'] as String? ?? '—';
                        final shortId = id.length > 8
                            ? id.substring(0, 8).toUpperCase()
                            : id.toUpperCase();
                        final total = _saleTotal(o);
                        final createdAt = (o['created_at'] as String? ?? '').length >= 10
                            ? (o['created_at'] as String).substring(0, 10)
                            : '';
                        return CheckboxListTile(
                          value: checked,
                          onChanged: (v) => setState(() {
                            if (v == true) {
                              _selectedIds.add(id);
                            } else {
                              _selectedIds.remove(id);
                            }
                          }),
                          activeColor: AppTheme.primary,
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                          title: Text(customer,
                              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                          subtitle: Text(
                            [shortId, createdAt].where((s) => s.isNotEmpty).join(' · '),
                            style: const TextStyle(color: Colors.white38, fontSize: 11),
                          ),
                          secondary: Text('${total.toStringAsFixed(0)} د.ل',
                              style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                        );
                      },
                    ),
                  ),
      ),
      const SizedBox(height: 10),
      // Live footer: N طلبية · إجمالي X د.ل
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          Text('${_selectedIds.length} طلبية',
              style: const TextStyle(color: AppTheme.primary, fontSize: 13, fontWeight: FontWeight.w700)),
          const Spacer(),
          Text('إجمالي ${totalSelected.toStringAsFixed(0)} د.ل',
              style: const TextStyle(color: AppTheme.primary, fontSize: 13, fontWeight: FontWeight.w700)),
        ]),
      ),
      if (_error != null) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.error.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(_error!, style: const TextStyle(color: AppTheme.error, fontSize: 12)),
        ),
      ],
      const SizedBox(height: 12),
      SizedBox(
        height: 48,
        child: ElevatedButton.icon(
          onPressed: (_submitting || _selectedIds.isEmpty) ? null : _submit,
          icon: _submitting
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check, size: 20),
          label: Text(_submitting ? 'جاري الإنشاء...' : 'إنشاء التسوية'),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
        ),
      ),
    ]);
  }
}

// ─── Financial stat cell ───────────────────────────────────
class _FinStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _FinStat({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
        ]),
      ),
    );
  }
}
