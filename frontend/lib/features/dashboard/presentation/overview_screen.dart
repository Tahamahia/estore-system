import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:estore_app/app/theme.dart';
import 'package:estore_app/core/providers.dart';

class OverviewScreen extends ConsumerWidget {
  const OverviewScreen({super.key});

  String _weekChange(num thisWeek, num lastWeek) {
    if (lastWeek == 0) return thisWeek > 0 ? '+100%' : '0%';
    final pct = ((thisWeek - lastWeek) / lastWeek * 100).round();
    return pct >= 0 ? '+$pct%' : '$pct%';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashState = ref.watch(dashboardProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stat Cards
          LayoutBuilder(
            builder: (context, constraints) {
              final crossCount = constraints.maxWidth > 1000 ? 4 : (constraints.maxWidth > 600 ? 2 : 1);
              return dashState.when(
                loading: () => GridView.count(
                  crossAxisCount: crossCount, shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 2.2,
                  children: List.generate(4, (_) => _buildShimmerCard()),
                ),
                error: (_, __) => _buildStaticCards(crossCount),
                data: (data) {
                  final totalOrders = (data['total_orders'] as num?) ?? 0;
                  final totalCustomers = (data['total_customers'] as num?) ?? 0;
                  final totalRevenue = (data['total_revenue_local'] as num?) ?? 0;
                  final actionItems = data['items_needing_action'] as Map<String, dynamic>? ?? {};
                  final unsorted = (actionItems['unsorted'] as num?) ?? 0;
                  final ordersThisWeek = (data['orders_this_week'] as num?) ?? 0;
                  final ordersLastWeek = (data['orders_last_week'] as num?) ?? 0;
                  final revenueThisWeek = (data['revenue_this_week'] as num?) ?? 0;
                  final revenueLastWeek = (data['revenue_last_week'] as num?) ?? 0;

                  return GridView.count(
                    crossAxisCount: crossCount, shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 2.2,
                    children: [
                      _StatCard(
                        title: 'إجمالي الطلبيات',
                        value: '$totalOrders',
                        icon: Icons.receipt_long,
                        color: AppTheme.primary,
                        change: _weekChange(ordersThisWeek, ordersLastWeek),
                      ),
                      _StatCard(
                        title: 'الإيرادات (د.ل)',
                        value: totalRevenue.toStringAsFixed(2),
                        icon: Icons.attach_money,
                        color: AppTheme.success,
                        change: _weekChange(revenueThisWeek, revenueLastWeek),
                      ),
                      _StatCard(
                        title: 'قيد المعالجة',
                        value: '$unsorted',
                        icon: Icons.inventory_2,
                        color: AppTheme.warning,
                        change: '—',
                        isNeutral: true,
                      ),
                      _StatCard(
                        title: 'الزبائن',
                        value: '$totalCustomers',
                        icon: Icons.people,
                        color: AppTheme.secondary,
                        change: '—',
                        isNeutral: true,
                      ),
                    ],
                  );
                },
              );
            },
          ),
          const SizedBox(height: 24),

          // Action Alerts
          dashState.maybeWhen(
            data: (data) => _buildActionAlerts(data),
            orElse: () => const SizedBox.shrink(),
          ),

          // Status Breakdown
          _StatusBreakdown(),
        ],
      ),
    );
  }

  Widget _buildActionAlerts(Map<String, dynamic> data) {
    final actionItems = data['items_needing_action'] as Map<String, dynamic>? ?? {};
    final pendingPurchase = (actionItems['pending_purchase'] as num?)?.toInt() ?? 0;
    final unsorted = (actionItems['unsorted'] as num?)?.toInt() ?? 0;
    final readyDispatch = (actionItems['ready_dispatch'] as num?)?.toInt() ?? 0;
    final cashWithDrivers = (actionItems['cash_with_drivers'] as num?)?.toDouble() ?? 0;

    final alerts = <_ActionAlert>[];
    if (pendingPurchase > 0) {
      alerts.add(_ActionAlert(
        icon: Icons.shopping_cart_outlined,
        color: AppTheme.warning,
        label: 'قطع تنتظر الشراء',
        count: pendingPurchase,
      ));
    }
    if (unsorted > 0) {
      alerts.add(_ActionAlert(
        icon: Icons.sort_rounded,
        color: AppTheme.accent,
        label: 'قطع تحتاج فرز',
        count: unsorted,
      ));
    }
    if (readyDispatch > 0) {
      alerts.add(_ActionAlert(
        icon: Icons.local_shipping_outlined,
        color: AppTheme.success,
        label: 'جاهزة للتوصيل',
        count: readyDispatch,
      ));
    }
    if (cashWithDrivers > 0) {
      alerts.add(_ActionAlert(
        icon: Icons.payments_outlined,
        color: AppTheme.warning,
        label: 'كاش مع المناديب لم يُسلَّم بعد',
        count: 0,
        valueLabel: '${cashWithDrivers.toStringAsFixed(0)} د.ل',
      ));
    }

    if (alerts.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('تنبيهات', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
        const SizedBox(height: 12),
        for (int i = 0; i < alerts.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          alerts[i],
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildShimmerCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }

  Widget _buildStaticCards(int crossCount) {
    return GridView.count(
      crossAxisCount: crossCount, shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 2.2,
      children: const [
        _StatCard(title: 'إجمالي الطلبيات', value: '--', icon: Icons.receipt_long, color: AppTheme.primary, change: '--'),
        _StatCard(title: 'الإيرادات (د.ل)', value: '--', icon: Icons.attach_money, color: AppTheme.success, change: '--'),
        _StatCard(title: 'قيد المعالجة', value: '--', icon: Icons.inventory_2, color: AppTheme.warning, change: '--', isNeutral: true),
        _StatCard(title: 'الزبائن', value: '--', icon: Icons.people, color: AppTheme.secondary, change: '--', isNeutral: true),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title, value, change;
  final IconData icon;
  final Color color;
  final bool isNeutral;
  const _StatCard({
    required this.title, required this.value, required this.icon,
    required this.color, required this.change, this.isNeutral = false,
  });

  @override
  Widget build(BuildContext context) {
    final isPositive = change.startsWith('+');
    final badgeBg = isNeutral || change == '—'
        ? Colors.white.withValues(alpha: 0.08)
        : (isPositive ? AppTheme.success : AppTheme.error).withValues(alpha: 0.15);
    final badgeText = isNeutral || change == '—'
        ? Colors.white54
        : (isPositive ? AppTheme.success : AppTheme.error);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(8)),
              child: Text(change, style: TextStyle(color: badgeText, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ]),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 4),
          Text(title, style: const TextStyle(fontSize: 13, color: Colors.white54)),
        ],
      ),
    );
  }
}

class _ActionAlert extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final int count;
  final String? valueLabel;
  const _ActionAlert({required this.icon, required this.color, required this.label, required this.count, this.valueLabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 14))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(valueLabel ?? '$count', style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 14)),
        ),
      ]),
    );
  }
}

class _StatusBreakdown extends ConsumerWidget {
  static const _statusColors = {
    'pending': AppTheme.warning,
    'paid': AppTheme.primary,
    'purchased': AppTheme.secondary,
    'shipped': Color(0xFF64B5F6),
    'arrived_warehouse': AppTheme.accent,
    'sorted': Color(0xFF26A69A),
    'ready_dispatch': Color(0xFF00BCD4),
    'dispatched': Color(0xFF66BB6A),
    'delivered': AppTheme.success,
    'cancelled': AppTheme.error,
    'refunded': Color(0xFFFF7043),
    'transferred_to_inventory': Color(0xFF78909C),
    'in_stock': Color(0xFF5C6BC0),
  };

  static String _translateStatus(String s) {
    const map = {
      'pending': 'معلق',
      'paid': 'مدفوع',
      'purchased': 'تم الشراء',
      'shipped': 'شُحن',
      'arrived_warehouse': 'وصل المستودع',
      'sorted': 'مفروز',
      'ready_dispatch': 'جاهز للتوصيل',
      'dispatched': 'خرج للتوصيل',
      'delivered': 'تم التوصيل',
      'cancelled': 'ملغي',
      'refunded': 'مسترجع',
      'transferred_to_inventory': 'في المخزون',
      'in_stock': 'في المخزون (فوري)',
    };
    return map[s] ?? s.replaceAll('_', ' ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashState = ref.watch(dashboardProvider);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: dashState.when(
        loading: () => const SizedBox(height: 280, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
        error: (_, __) => const SizedBox(height: 280, child: Center(child: Text('لا توجد بيانات', style: TextStyle(color: Colors.white38)))),
        data: (data) {
          final statusCounts = Map<String, dynamic>.from(data['status_counts'] as Map? ?? {});
          if (statusCounts.isEmpty) {
            return const SizedBox(height: 280, child: Center(child: Text('لا توجد بيانات حالات', style: TextStyle(color: Colors.white38))));
          }

          final total = statusCounts.values.fold<num>(0, (sum, v) => sum + ((v as num?) ?? 0));
          final sections = <PieChartSectionData>[];
          final legends = <Widget>[];

          for (final entry in statusCounts.entries) {
            final value = (entry.value as num?)?.toDouble() ?? 0;
            if (value <= 0) continue;
            final pct = total > 0 ? (value / total * 100).round() : 0;
            final color = _statusColors[entry.key] ?? AppTheme.accent;
            sections.add(PieChartSectionData(
              value: value, title: '$pct%', color: color, radius: 50,
              titleStyle: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
            ));
            legends.add(_LegendItem(
              color: color,
              label: _translateStatus(entry.key),
              value: '${value.toInt()} ($pct%)',
            ));
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('توزيع القطع حسب الحالة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
              const SizedBox(height: 24),
              SizedBox(
                height: 200,
                child: PieChart(PieChartData(
                  sectionsSpace: 3, centerSpaceRadius: 40,
                  sections: sections,
                )),
              ),
              const SizedBox(height: 16),
              ...legends,
            ],
          );
        },
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label, value;
  const _LegendItem({required this.color, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        const Spacer(),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
      ]),
    );
  }
}
