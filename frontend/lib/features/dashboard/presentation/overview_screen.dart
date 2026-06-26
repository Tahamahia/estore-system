import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:estore_app/app/theme.dart';

class OverviewScreen extends StatelessWidget {
  const OverviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats Cards Row
          LayoutBuilder(
            builder: (context, constraints) {
              final crossCount = constraints.maxWidth > 1000 ? 4 : (constraints.maxWidth > 600 ? 2 : 1);
              return GridView.count(
                crossAxisCount: crossCount,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 2.2,
                children: const [
                  _StatCard(title: 'Total Orders', value: '1,247', icon: Icons.receipt_long, color: AppTheme.primary, change: '+12.5%'),
                  _StatCard(title: 'Pending Sort', value: '89', icon: Icons.inventory_2, color: AppTheme.warning, change: '-3.2%'),
                  _StatCard(title: 'Revenue', value: '\$45,820', icon: Icons.attach_money, color: AppTheme.success, change: '+8.1%'),
                  _StatCard(title: 'Active Customers', value: '342', icon: Icons.people, color: AppTheme.secondary, change: '+5.7%'),
                ],
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
              return Column(
                children: [
                  _OrdersChart(),
                  const SizedBox(height: 24),
                  _StatusBreakdown(),
                ],
              );
            },
          ),
          const SizedBox(height: 24),

          // Recent Orders Table
          _RecentOrdersTable(),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String change;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.change,
  });

  @override
  Widget build(BuildContext context) {
    final isPositive = change.startsWith('+');
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
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
                child: Text(
                  change,
                  style: TextStyle(
                    color: isPositive ? AppTheme.success : AppTheme.error,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 4),
          Text(title, style: const TextStyle(fontSize: 13, color: Colors.white54)),
        ],
      ),
    );
  }
}

class _OrdersChart extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Order Trends', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
          const SizedBox(height: 24),
          SizedBox(
            height: 240,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 20,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: AppTheme.darkBorder.withValues(alpha: 0.5),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                        if (value.toInt() >= 0 && value.toInt() < days.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(days[value.toInt()], style: const TextStyle(color: Colors.white38, fontSize: 12)),
                          );
                        }
                        return const SizedBox();
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: const [
                      FlSpot(0, 35), FlSpot(1, 48), FlSpot(2, 42), FlSpot(3, 65),
                      FlSpot(4, 55), FlSpot(5, 72), FlSpot(6, 58),
                    ],
                    isCurved: true,
                    gradient: const LinearGradient(colors: [AppTheme.primary, AppTheme.secondary]),
                    barWidth: 3,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [AppTheme.primary.withValues(alpha: 0.3), Colors.transparent],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBreakdown extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Status Breakdown', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
          const SizedBox(height: 24),
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                sectionsSpace: 3,
                centerSpaceRadius: 40,
                sections: [
                  PieChartSectionData(value: 35, title: '35%', color: AppTheme.primary, radius: 50, titleStyle: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                  PieChartSectionData(value: 25, title: '25%', color: AppTheme.success, radius: 50, titleStyle: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                  PieChartSectionData(value: 20, title: '20%', color: AppTheme.warning, radius: 50, titleStyle: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                  PieChartSectionData(value: 20, title: '20%', color: AppTheme.secondary, radius: 50, titleStyle: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _LegendItem(color: AppTheme.primary, label: 'Pending', value: '35%'),
          const _LegendItem(color: AppTheme.success, label: 'Delivered', value: '25%'),
          const _LegendItem(color: AppTheme.warning, label: 'In Transit', value: '20%'),
          const _LegendItem(color: AppTheme.secondary, label: 'Sorting', value: '20%'),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final String value;
  const _LegendItem({required this.color, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const Spacer(),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }
}

class _RecentOrdersTable extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text('Recent Orders', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
              Spacer(),
              Text('View All →', style: TextStyle(color: AppTheme.primary, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(AppTheme.darkCard.withValues(alpha: 0.5)),
              columns: const [
                DataColumn(label: Text('Order ID', style: TextStyle(color: Colors.white70))),
                DataColumn(label: Text('Customer', style: TextStyle(color: Colors.white70))),
                DataColumn(label: Text('Items', style: TextStyle(color: Colors.white70))),
                DataColumn(label: Text('Total', style: TextStyle(color: Colors.white70))),
                DataColumn(label: Text('Status', style: TextStyle(color: Colors.white70))),
              ],
              rows: [
                _buildRow('ORD-001', 'Ahmed Ali', '3', '\$125.00', 'Pending', AppTheme.warning),
                _buildRow('ORD-002', 'Sara Hassan', '1', '\$45.50', 'Delivered', AppTheme.success),
                _buildRow('ORD-003', 'Mohamed Ibrahim', '5', '\$320.00', 'Sorting', AppTheme.secondary),
                _buildRow('ORD-004', 'Fatima Salem', '2', '\$89.99', 'In Transit', AppTheme.primary),
              ],
            ),
          ),
        ],
      ),
    );
  }

  DataRow _buildRow(String id, String customer, String items, String total, String status, Color statusColor) {
    return DataRow(cells: [
      DataCell(Text(id, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500))),
      DataCell(Text(customer, style: const TextStyle(color: Colors.white70))),
      DataCell(Text(items, style: const TextStyle(color: Colors.white70))),
      DataCell(Text(total, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
      DataCell(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(status, style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ),
    ]);
  }
}
