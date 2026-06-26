import 'package:flutter/material.dart';
import 'package:estore_app/app/theme.dart';

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with actions
          Row(
            children: [
              const Text('All Orders', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white)),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.add, size: 20),
                label: const Text('New Order'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Filters
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _FilterChip(label: 'All', selected: true),
              _FilterChip(label: 'Pending'),
              _FilterChip(label: 'Purchased'),
              _FilterChip(label: 'In Transit'),
              _FilterChip(label: 'Delivered'),
            ],
          ),
          const SizedBox(height: 20),

          // Search
          TextField(
            decoration: InputDecoration(
              hintText: 'Search orders by ID, customer, or product...',
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: const Icon(Icons.search, color: Colors.white38),
              filled: true,
              fillColor: AppTheme.darkCard,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 20),

          // Orders List
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.darkSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.darkBorder),
              ),
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: 10,
                separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.darkBorder),
                itemBuilder: (context, index) {
                  return _OrderTile(index: index);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  const _FilterChip({required this.label, this.selected = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? AppTheme.primary : AppTheme.darkCard,
        borderRadius: BorderRadius.circular(20),
        border: selected ? null : Border.all(color: AppTheme.darkBorder),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.white : Colors.white70,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  final int index;
  const _OrderTile({required this.index});

  @override
  Widget build(BuildContext context) {
    final statuses = ['Pending', 'Purchased', 'In Transit', 'Delivered', 'Sorting'];
    final colors = [AppTheme.warning, AppTheme.primary, AppTheme.secondary, AppTheme.success, AppTheme.accent];
    final status = statuses[index % statuses.length];
    final color = colors[index % colors.length];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.receipt_outlined, color: color, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ORD-${(1000 + index).toString()}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('Customer ${index + 1} • ${index + 1} items', style: const TextStyle(color: Colors.white54, fontSize: 13)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('\$${(50 + index * 35).toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(status, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
