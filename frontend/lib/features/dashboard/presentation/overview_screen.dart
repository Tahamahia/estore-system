import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:estore_app/app/theme.dart';
import 'package:estore_app/core/providers.dart';

class OverviewScreen extends ConsumerWidget {
  const OverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashState = ref.watch(dashboardProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats Cards
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
                  // Backend returns stats at root level — no 'stats' wrapper key.
                  // Action items are nested under items_needing_action.
                  final totalOrders = data['total_orders'] ?? 0;
                  final totalCustomers = data['total_customers'] ?? 0;
                  final totalRevenue = data['total_revenue_local'] ?? 0;
                  final actionItems = data['items_needing_action'] as Map<String, dynamic>? ?? {};
                  final unsorted = actionItems['unsorted'] ?? 0;
                  final revenue = (totalRevenue as num).toStringAsFixed(2);
                  return GridView.count(
                    crossAxisCount: crossCount, shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 2.2,
                    children: [
                      _StatCard(title: 'Total Orders', value: '$totalOrders',
                        icon: Icons.receipt_long, color: AppTheme.primary, change: '+0%'),
                      _StatCard(title: 'Pending Sort', value: '$unsorted',
                        icon: Icons.inventory_2, color: AppTheme.warning, change: '0%'),
                      _StatCard(title: 'Revenue (Local)', value: revenue,
                        icon: Icons.attach_money, color: AppTheme.success, change: '+0%'),
                      _StatCard(title: 'Customers', value: '$totalCustomers',
                        icon: Icons.people, color: AppTheme.secondary, change: '+0%'),
                    ],
                  );
                },
              );
            },
          ),
          const SizedBox(height: 24),

          // Charts Row
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth > 800) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: _OrdersChart()),
                    const SizedBox(width: 24),
                    Expanded(flex: 2, child: _StatusBreakdown()),
                  ],
                );
              }
              return Column(children: [
                _OrdersChart(),
                const SizedBox(height: 24),
                _StatusBreakdown(),
              ]);
            },
          ),
        ],
      ),
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
        _StatCard(title: 'Total Orders', value: '--', icon: Icons.receipt_long, color: AppTheme.primary, change: '--'),
        _StatCard(title: 'Pending Sort', value: '--', icon: Icons.inventory_2, color: AppTheme.warning, change: '--'),
        _StatCard(title: 'Revenue', value: '--', icon: Icons.attach_money, color: AppTheme.success, change: '--'),
        _StatCard(title: 'Active Customers', value: '--', icon: Icons.people, color: AppTheme.secondary, change: '--'),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title, value, change;
  final IconData icon;
  final Color color;
  const _StatCard({required this.title, required this.value, required this.icon, required this.color, required this.change});

  @override
  Widget build(BuildContext context) {
    final isPositive = change.startsWith('+');
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
              decoration: BoxDecoration(
                color: (isPositive ? AppTheme.success : AppTheme.error).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(change, style: TextStyle(
                color: isPositive ? AppTheme.success : AppTheme.error,
                fontSize: 12, fontWeight: FontWeight.w600,
              )),
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

class _OrdersChart extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashState = ref.watch(dashboardProvider);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Order Status Overview', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
          const SizedBox(height: 24),
          SizedBox(
            height: 240,
            child: dashState.when(
              loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              error: (_, __) => const Center(child: Text('No data', style: TextStyle(color: Colors.white38))),
              data: (data) {
                final statusCounts = Map<String, dynamic>.from(data['status_counts'] as Map? ?? {});
                if (statusCounts.isEmpty) {
                  return const Center(child: Text('No order data', style: TextStyle(color: Colors.white38)));
                }

                final entries = statusCounts.entries.toList();
                final barGroups = <BarChartGroupData>[];
                final statusColors = <Color>[
                  AppTheme.warning, AppTheme.primary, AppTheme.secondary,
                  AppTheme.success, AppTheme.error, AppTheme.accent,
                  Colors.purpleAccent, Colors.tealAccent,
                ];

                for (var i = 0; i < entries.length; i++) {
                  final value = (entries[i].value as num?)?.toDouble() ?? 0;
                  barGroups.add(BarChartGroupData(
                    x: i,
                    barRods: [BarChartRodData(
                      toY: value,
                      color: statusColors[i % statusColors.length],
                      width: 18,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                    )],
                  ));
                }

                return BarChart(BarChartData(
                  gridData: FlGridData(
                    show: true, drawVerticalLine: false, horizontalInterval: 10,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: AppTheme.darkBorder.withValues(alpha: 0.5), strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(sideTitles: SideTitles(
                      showTitles: true, reservedSize: 40,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx >= 0 && idx < entries.length) {
                          final label = entries[idx].key.replaceAll('_', '\n');
                          return Padding(padding: const EdgeInsets.only(top: 6),
                            child: Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9), textAlign: TextAlign.center));
                        }
                        return const SizedBox();
                      },
                    )),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: barGroups,
                ));
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBreakdown extends ConsumerWidget {
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
        error: (_, __) => const SizedBox(height: 280, child: Center(child: Text('No data', style: TextStyle(color: Colors.white38)))),
        data: (data) {
          final statusCounts = Map<String, dynamic>.from(data['status_counts'] as Map? ?? {});
          if (statusCounts.isEmpty) {
            return const SizedBox(height: 280, child: Center(child: Text('No status data', style: TextStyle(color: Colors.white38))));
          }

          final total = statusCounts.values.fold<num>(0, (sum, v) => sum + ((v as num?) ?? 0));
          final statusColors = {
            'pending_payment': AppTheme.warning,
            'paid': AppTheme.primary,
            'purchased': AppTheme.primary,
            'shipped': AppTheme.secondary,
            'arrived_warehouse': AppTheme.accent,
            'sorted': AppTheme.secondary,
            'ready_dispatch': Colors.tealAccent,
            'dispatched': AppTheme.success,
            'delivered': AppTheme.success,
            'cancelled': AppTheme.error,
            'auto_cancelled': AppTheme.error,
          };

          final sections = <PieChartSectionData>[];
          final legends = <Widget>[];

          for (final entry in statusCounts.entries) {
            final value = (entry.value as num?)?.toDouble() ?? 0;
            if (value <= 0) continue;
            final pct = total > 0 ? (value / total * 100).round() : 0;
            final color = statusColors[entry.key] ?? AppTheme.accent;
            sections.add(PieChartSectionData(
              value: value, title: '$pct%', color: color, radius: 50,
              titleStyle: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
            ));
            legends.add(_LegendItem(
              color: color,
              label: entry.key.replaceAll('_', ' '),
              value: '${value.toInt()} ($pct%)',
            ));
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Status Breakdown', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
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

