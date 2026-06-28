import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:estore_app/app/theme.dart';
import 'package:estore_app/core/providers.dart';
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});
  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    Future.microtask(() => ref.read(customersProvider.notifier).fetchCustomers());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabCtrl.dispose();
    super.dispose();
  }

  void _showAddDialog() {
    showDialog(context: context, builder: (_) => _AddCustomerDialog(
      onCreated: () => ref.read(customersProvider.notifier).fetchCustomers(),
    ));
  }

  void _openWhatsApp(String? phone, String name, {int itemCount = 0, String status = 'in progress'}) async {
    if (phone == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No phone number'), backgroundColor: AppTheme.warning));
      return;
    }
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final msg = Uri.encodeComponent('Hello $name, your order of $itemCount items is currently $status.');
    final url = Uri.parse('https://wa.me/$cleanPhone?text=$msg');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('Customers', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white)),
          const Spacer(),
          ElevatedButton.icon(onPressed: _showAddDialog, icon: const Icon(Icons.person_add, size: 20), label: const Text('Add Customer')),
        ]),
        const SizedBox(height: 16),
        // Tabs: All Customers | Dispatch Status
        Container(
          decoration: BoxDecoration(color: AppTheme.darkSurface, borderRadius: BorderRadius.circular(12)),
          child: TabBar(
            controller: _tabCtrl,
            indicator: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
            indicatorSize: TabBarIndicatorSize.tab,
            labelColor: AppTheme.primary,
            unselectedLabelColor: Colors.white54,
            dividerColor: Colors.transparent,
            tabs: const [
              Tab(text: '👥 All Customers'),
              Tab(text: '🚦 Dispatch Status'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: TabBarView(controller: _tabCtrl, children: [
            _buildCustomersList(),
            _DispatchStatusTab(onWhatsApp: _openWhatsApp),
          ]),
        ),
      ]),
    );
  }

  Widget _buildCustomersList() {
    final state = ref.watch(customersProvider);
    return Column(children: [
      TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search customers...', hintStyle: const TextStyle(color: Colors.white38),
          prefixIcon: const Icon(Icons.search, color: Colors.white38),
          filled: true, fillColor: AppTheme.darkCard,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
        style: const TextStyle(color: Colors.white),
      ),
      const SizedBox(height: 16),
      Expanded(
        child: Container(
          decoration: BoxDecoration(color: AppTheme.darkSurface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.darkBorder)),
          child: state.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.error_outline, color: AppTheme.error, size: 48), const SizedBox(height: 12),
              const Text('Failed to load', style: TextStyle(color: Colors.white70)), const SizedBox(height: 8),
              ElevatedButton(onPressed: () => ref.read(customersProvider.notifier).fetchCustomers(), child: const Text('Retry')),
            ])),
            data: (customers) => customers.isEmpty
              ? const Center(child: Text('No customers yet', style: TextStyle(color: Colors.white38)))
              : ListView.separated(
                  padding: const EdgeInsets.all(16), itemCount: customers.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.darkBorder),
                  itemBuilder: (context, index) {
                    final c = customers[index];
                    final name = c['full_name'] ?? 'Unknown';
                    final phone = c['phone'] as String?;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                      leading: CircleAvatar(
                        backgroundColor: AppTheme.primary.withValues(alpha: 0.2),
                        child: Text(name[0], style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
                      ),
                      title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                      subtitle: Text(phone ?? '', style: const TextStyle(color: Colors.white54, fontSize: 13)),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (phone != null && phone.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.chat_rounded, color: Color(0xFF25D366), size: 22),
                            tooltip: 'WhatsApp',
                            onPressed: () => _openWhatsApp(phone, name),
                          ),
                        if (c['city'] != null) Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: AppTheme.secondary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                          child: Text(c['city'], style: const TextStyle(color: AppTheme.secondary, fontSize: 12)),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.chevron_right, color: Colors.white38),
                      ]),
                    );
                  },
                ),
          ),
        ),
      ),
    ]);
  }
}

// ─── Dispatch Status Tab (Traffic Lights) ────────────────────
class _DispatchStatusTab extends ConsumerStatefulWidget {
  final void Function(String? phone, String name, {int itemCount, String status}) onWhatsApp;
  const _DispatchStatusTab({required this.onWhatsApp});
  @override
  ConsumerState<_DispatchStatusTab> createState() => _DispatchStatusTabState();
}

class _DispatchStatusTabState extends ConsumerState<_DispatchStatusTab> {
  List<Map<String, dynamic>>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ref.read(ordersProvider.notifier).fetchDispatchStatus();
      if (mounted) setState(() { _data = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_data == null || _data!.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.check_circle_outline, size: 56, color: Colors.white.withValues(alpha: 0.2)),
        const SizedBox(height: 12),
        const Text('No pending dispatches', style: TextStyle(color: Colors.white38)),
      ]));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(8), itemCount: _data!.length,
        itemBuilder: (ctx, i) {
          final d = _data![i];
          final total = (d['total_items'] as num?)?.toInt() ?? 0;
          final ready = (d['ready_items'] as num?)?.toInt() ?? 0;
          final pending = (d['pending_items'] as num?)?.toInt() ?? 0;
          final notOrdered = (d['not_ordered_items'] as num?)?.toInt() ?? 0;
          final name = d['customer_name'] as String? ?? 'Unknown';
          final phone = d['phone'] as String?;

          // Traffic light logic
          final bool isGreen = total > 0 && ready == total;
          final bool isRed = pending > 0 || notOrdered > 0;
          final trafficColor = isGreen ? AppTheme.success : isRed ? AppTheme.error : AppTheme.warning;
          final trafficLabel = isGreen ? 'READY' : isRed ? 'PARTIAL' : 'WAITING';
          final statusMsg = isGreen ? 'ready for delivery' : 'partially received ($ready/$total arrived)';

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.darkSurface, borderRadius: BorderRadius.circular(14),
              border: Border.all(color: trafficColor.withValues(alpha: 0.4)),
            ),
            child: Row(children: [
              // Traffic light indicator
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: trafficColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(child: Icon(
                  isGreen ? Icons.check_circle_rounded : Icons.pending_rounded,
                  color: trafficColor, size: 28,
                )),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: trafficColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
                    child: Text(trafficLabel, style: TextStyle(color: trafficColor, fontSize: 10, fontWeight: FontWeight.w700)),
                  ),
                ]),
                const SizedBox(height: 4),
                Text('$ready/$total items sorted • ${pending > 0 ? '$pending in transit' : ''}${notOrdered > 0 ? ' • $notOrdered not ordered' : ''}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
                // Progress bar
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: total > 0 ? ready / total : 0,
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    color: trafficColor,
                    minHeight: 6,
                  ),
                ),
              ])),
              const SizedBox(width: 10),
              // WhatsApp button
              if (phone != null && phone.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.chat_rounded, color: Color(0xFF25D366), size: 24),
                  tooltip: 'WhatsApp $name',
                  onPressed: () => widget.onWhatsApp(phone, name, itemCount: total, status: statusMsg),
                ),
            ]),
          );
        },
      ),
    );
  }
}

// ─── Add Customer Dialog (unchanged) ─────────────────────────
class _AddCustomerDialog extends ConsumerStatefulWidget {
  final VoidCallback onCreated;
  const _AddCustomerDialog({required this.onCreated});
  @override
  ConsumerState<_AddCustomerDialog> createState() => _AddCustomerDialogState();
}

class _AddCustomerDialogState extends ConsumerState<_AddCustomerDialog> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() { _nameCtrl.dispose(); _phoneCtrl.dispose(); _cityCtrl.dispose(); super.dispose(); }

  Future<void> _create() async {
    if (_nameCtrl.text.isEmpty) { setState(() => _error = 'Name is required'); return; }
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(customersProvider.notifier).createCustomer({
        'id': const Uuid().v4(), 'full_name': _nameCtrl.text, 'phone': _phoneCtrl.text, 'city': _cityCtrl.text,
      });
      widget.onCreated();
      if (mounted) Navigator.of(context).pop();
    } catch (e) { setState(() => _error = e.toString()); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Add Customer', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white)),
            const SizedBox(height: 24),
            if (_error != null) Container(
              padding: const EdgeInsets.all(10), margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: AppTheme.error.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
              child: Text(_error!, style: const TextStyle(color: AppTheme.error, fontSize: 13)),
            ),
            TextField(controller: _nameCtrl, style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Full Name', prefixIcon: Icon(Icons.person))),
            const SizedBox(height: 12),
            TextField(controller: _phoneCtrl, style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Phone', prefixIcon: Icon(Icons.phone))),
            const SizedBox(height: 12),
            TextField(controller: _cityCtrl, style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'City', prefixIcon: Icon(Icons.location_city))),
            const SizedBox(height: 24),
            SizedBox(height: 48, child: ElevatedButton(
              onPressed: _loading ? null : _create,
              child: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Add Customer'),
            )),
          ]),
        ),
      ),
    );
  }
}
