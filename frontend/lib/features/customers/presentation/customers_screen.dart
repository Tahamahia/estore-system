import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:estore_app/app/theme.dart';
import 'package:estore_app/core/providers.dart';
import 'package:uuid/uuid.dart';

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(customersProvider.notifier).fetchCustomers());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showAddDialog() {
    showDialog(context: context, builder: (_) => _AddCustomerDialog(
      onCreated: () => ref.read(customersProvider.notifier).fetchCustomers(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(customersProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('Customers', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white)),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: _showAddDialog,
              icon: const Icon(Icons.person_add, size: 20),
              label: const Text('Add Customer'),
            ),
          ]),
          const SizedBox(height: 20),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search customers...',
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: const Icon(Icons.search, color: Colors.white38),
              filled: true, fillColor: AppTheme.darkCard,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 20),
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
                    const Text('Failed to load customers', style: TextStyle(color: Colors.white70)),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () => ref.read(customersProvider.notifier).fetchCustomers(),
                      child: const Text('Retry'),
                    ),
                  ],
                )),
                data: (customers) => customers.isEmpty
                    ? const Center(child: Text('No customers yet', style: TextStyle(color: Colors.white38)))
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: customers.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.darkBorder),
                        itemBuilder: (context, index) {
                          final c = customers[index];
                          final name = c['full_name'] ?? 'Unknown';
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                            leading: CircleAvatar(
                              backgroundColor: AppTheme.primary.withValues(alpha: 0.2),
                              child: Text(name[0], style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
                            ),
                            title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                            subtitle: Text(c['phone'] ?? '', style: const TextStyle(color: Colors.white54, fontSize: 13)),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              if (c['city'] != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppTheme.secondary.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
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
        ],
      ),
    );
  }
}

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
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_nameCtrl.text.isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(customersProvider.notifier).createCustomer({
        'id': const Uuid().v4(),
        'full_name': _nameCtrl.text,
        'phone': _phoneCtrl.text,
        'city': _cityCtrl.text,
      });
      widget.onCreated();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
            if (_error != null)
              Container(
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
              child: _loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Add Customer'),
            )),
          ]),
        ),
      ),
    );
  }
}
