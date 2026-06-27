import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:estore_app/app/theme.dart';
import 'package:estore_app/core/providers.dart';

class ShipmentsScreen extends ConsumerStatefulWidget {
  const ShipmentsScreen({super.key});

  @override
  ConsumerState<ShipmentsScreen> createState() => _ShipmentsScreenState();
}

class _ShipmentsScreenState extends ConsumerState<ShipmentsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(shipmentsProvider.notifier).fetchShipments());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(shipmentsProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
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
          ]),
          const SizedBox(height: 24),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.darkSurface, borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.darkBorder),
              ),
              child: state.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: AppTheme.error, size: 48),
                    const SizedBox(height: 12),
                    const Text('Failed to load shipments', style: TextStyle(color: Colors.white70)),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () => ref.read(shipmentsProvider.notifier).fetchShipments(),
                      child: const Text('Retry'),
                    ),
                  ],
                )),
                data: (shipments) => shipments.isEmpty
                    ? const Center(child: Text('No shipments found', style: TextStyle(color: Colors.white38)))
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: shipments.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.darkBorder),
                        itemBuilder: (context, index) {
                          final s = shipments[index];
                          final status = (s['status'] ?? 'pending') as String;
                          final color = _statusColor(status);
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                            leading: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(Icons.local_shipping, color: color, size: 22),
                            ),
                            title: Text(s['tracking_number'] ?? s['id'] ?? '',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                            subtitle: Text('${s['carrier'] ?? 'Unknown'} • ${s['items_count'] ?? '?'} items',
                              style: const TextStyle(color: Colors.white54, fontSize: 13)),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(status.replaceAll('_', ' '),
                                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'in_transit': return AppTheme.secondary;
      case 'arrived': case 'delivered': return AppTheme.success;
      case 'processing': return AppTheme.warning;
      default: return AppTheme.primary;
    }
  }
}
