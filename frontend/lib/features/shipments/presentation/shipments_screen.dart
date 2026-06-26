import 'package:flutter/material.dart';
import 'package:estore_app/app/theme.dart';

class ShipmentsScreen extends StatelessWidget {
  const ShipmentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Shipments', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white)),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.add, size: 20),
                label: const Text('New Shipment'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.inventory, size: 20),
                label: const Text('Master Shipment'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.secondary,
                  side: const BorderSide(color: AppTheme.secondary),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.darkSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.darkBorder),
              ),
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: 8,
                separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.darkBorder),
                itemBuilder: (context, index) {
                  final statuses = ['In Transit', 'Arrived', 'Processing', 'Pending'];
                  final colors = [AppTheme.secondary, AppTheme.success, AppTheme.warning, AppTheme.primary];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colors[index % 4].withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.local_shipping, color: colors[index % 4], size: 22),
                    ),
                    title: Text('TRK-${900000 + index}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    subtitle: Text('Supplier ${index + 1} • ${index + 2} items', style: const TextStyle(color: Colors.white54, fontSize: 13)),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: colors[index % 4].withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(statuses[index % 4], style: TextStyle(color: colors[index % 4], fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
