import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:estore_app/app/theme.dart';
import 'package:estore_app/core/providers.dart';

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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(settlementsProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('التسويات المالية', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white)),
            const Spacer(),
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
    );
  }
}

class _SettlementCard extends StatelessWidget {
  final Map<String, dynamic> settlement;
  const _SettlementCard({required this.settlement});

  String _formatDate(String raw) {
    if (raw.length < 10) return raw.isEmpty ? '—' : raw;
    final parts = raw.substring(0, 10).split('-');
    if (parts.length < 3) return raw.substring(0, 10);
    return '${parts[2]}/${parts[1]}/${parts[0]}';
  }

  @override
  Widget build(BuildContext context) {
    final name = settlement['name'] as String? ?? '—';
    final exchangeRate = (settlement['exchange_rate'] as num?)?.toDouble() ?? 0;
    final createdAt = settlement['created_at'] as String? ?? '';
    final totalLyd = (settlement['total_lyd_collected'] as num?)?.toDouble() ?? 0;
    final totalUsdCost = (settlement['total_usd_cost'] as num?)?.toDouble() ?? 0;
    final writeOffUsd = (settlement['total_write_off_usd'] as num?)?.toDouble() ?? 0;
    final writeOffCount = (settlement['write_off_item_count'] as num?)?.toInt() ?? 0;
    final orderCount = (settlement['order_count'] as num?)?.toInt() ?? 0;

    // Core financial calculations — write-offs are an expense against this settlement
    final boughtUsd = exchangeRate > 0 ? totalLyd / exchangeRate : 0.0;
    final netProfit = boughtUsd - totalUsdCost - writeOffUsd;
    final isProfit = netProfit >= 0;

    return Container(
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
      ]),
    );
  }
}

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
