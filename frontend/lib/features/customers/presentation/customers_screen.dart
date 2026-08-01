import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:estore_app/app/theme.dart';
import 'package:estore_app/core/providers.dart';
import 'package:estore_app/core/utils/dialog_utils.dart';
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});
  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  String _searchText = '';
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    Future.microtask(() => ref.read(customersProvider.notifier).fetchCustomers());
    _searchController.addListener(() {
      setState(() => _searchText = _searchController.text.trim().toLowerCase());
    });
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

  void _showEditDialog(Map<String, dynamic> customer) {
    showDialog(context: context, builder: (_) => _EditCustomerDialog(
      customer: customer,
      onUpdated: () => ref.read(customersProvider.notifier).fetchCustomers(),
    ));
  }

  String _translateStatus(String status) {
    switch (status) {
      case 'pending':              return 'في الانتظار';
      case 'purchased':            return 'تم الشراء';
      case 'shipped':              return 'في الشحن';
      case 'arrived_warehouse':    return 'وصل المخزن';
      case 'sorted':               return 'تم الفرز';
      case 'ready_dispatch':       return 'جاهز للتوصيل';
      case 'dispatched':           return 'مع المندوب';
      case 'delivered':            return 'تم التوصيل';
      case 'cancelled':            return 'ملغي';
      case 'refunded':             return 'مسترد';
      case 'transferred_to_inventory': return 'بضاعة فورية';
      case 'in_stock':             return 'فوري';
      default:                     return status.replaceAll('_', ' ');
    }
  }

  Future<void> _confirmDelete(BuildContext context, Map<String, dynamic> customer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.darkSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('حذف الزبون', style: TextStyle(color: Colors.white)),
        content: Text(
          'هل تريد حذف "${customer['full_name']}"؟ لا يمكن التراجع عن هذا الإجراء.',
          style: const TextStyle(color: Colors.white70),
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
    await ref.read(customersProvider.notifier).deleteCustomer(customer['id'] as String);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تم حذف الزبون'),
        backgroundColor: AppTheme.success,
      ));
    }
  }

  void _openWhatsApp(String? phone, String name, {int itemCount = 0, String status = 'in progress'}) async {
    if (phone == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يوجد رقم هاتف'), backgroundColor: AppTheme.warning));
      return;
    }
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final translatedStatus = _translateStatus(status);
    final msg = Uri.encodeComponent('مرحبا $name، طلبك المكون من $itemCount عناصر حالته: $translatedStatus.');
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
          const Text('الزبائن', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white)),
          const Spacer(),
          ElevatedButton.icon(onPressed: _showAddDialog, icon: const Icon(Icons.person_add, size: 20), label: const Text('إضافة زبون')),
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
              Tab(text: '👥 كل الزبائن'),
              Tab(text: '🚦 حالة التوصيل'),
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
          hintText: 'بحث بالاسم أو الهاتف...', hintStyle: const TextStyle(color: Colors.white38),
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
              const Text('فشل التحميل', style: TextStyle(color: Colors.white70)), const SizedBox(height: 8),
              ElevatedButton(onPressed: () => ref.read(customersProvider.notifier).fetchCustomers(), child: const Text('إعادة المحاولة')),
            ])),
            data: (customers) {
              // Apply local search filter
              final filtered = _searchText.isEmpty ? customers : customers.where((c) {
                final name = (c['full_name'] as String? ?? '').toLowerCase();
                final phone = (c['phone'] as String? ?? '').toLowerCase();
                final city = (c['city'] as String? ?? '').toLowerCase();
                return name.contains(_searchText) ||
                    phone.contains(_searchText) ||
                    city.contains(_searchText);
              }).toList();

              if (filtered.isEmpty) {
                return const Center(child: Text('لا يوجد زبائن', style: TextStyle(color: Colors.white38)));
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16), itemCount: filtered.length,
                separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.darkBorder),
                itemBuilder: (context, index) {
                  final c = filtered[index];
                  final name = c['full_name'] ?? 'Unknown';
                  final phone = c['phone'] as String?;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                    onTap: () => _showEditDialog(c),
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
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: AppTheme.error, size: 20),
                        tooltip: 'حذف الزبون',
                        onPressed: () => _confirmDelete(context, c),
                      ),
                      const Icon(Icons.chevron_right, color: Colors.white38),
                    ]),
                  );
                },
              );
            },
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
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final data = await ref.read(ordersProvider.notifier).fetchDispatchStatus();
      if (mounted) setState(() { _data = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    // Show explicit error state with retry — never silently show "no data" on failure
    if (_error != null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.cloud_off_rounded, color: AppTheme.error, size: 56),
        const SizedBox(height: 16),
        const Text('فشل تحميل البيانات', style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text(_error!, style: const TextStyle(color: Colors.white38, fontSize: 12), textAlign: TextAlign.center),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh, size: 20),
          label: const Text('إعادة المحاولة'),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
        ),
      ]));
    }

    if (_data == null || _data!.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.check_circle_outline, size: 56, color: Colors.white.withValues(alpha: 0.2)),
        const SizedBox(height: 12),
        const Text('لا توجد طلبيات جارية', style: TextStyle(color: Colors.white38)),
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
          final trafficLabel = isGreen ? 'جاهز' : isRed ? 'جزئي' : 'في الانتظار';
          final statusMsg = isGreen ? 'جاهز للتوصيل' : 'وصل جزئياً ($ready/$total)';

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
                Text('$ready من $total مفروز${pending > 0 ? ' • $pending في الطريق' : ''}${notOrdered > 0 ? ' • $notOrdered لم يُطلب' : ''}',
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

// ─── Add Customer Dialog ─────────────────────────────────────
class _AddCustomerDialog extends ConsumerStatefulWidget {
  final VoidCallback onCreated;
  const _AddCustomerDialog({required this.onCreated});
  @override
  ConsumerState<_AddCustomerDialog> createState() => _AddCustomerDialogState();
}

class _AddCustomerDialogState extends ConsumerState<_AddCustomerDialog> {
  final _nameCtrl        = TextEditingController();
  final _phoneCtrl       = TextEditingController();
  final _phone2Ctrl      = TextEditingController();
  final _cityCtrl        = TextEditingController();
  final _areaCtrl        = TextEditingController();
  final _streetCtrl      = TextEditingController();
  final _locationUrlCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose(); _phoneCtrl.dispose(); _phone2Ctrl.dispose();
    _cityCtrl.dispose(); _areaCtrl.dispose(); _streetCtrl.dispose();
    _locationUrlCtrl.dispose(); super.dispose();
  }

  Future<void> _create() async {
    if (_nameCtrl.text.isEmpty) { setState(() => _error = 'الاسم مطلوب'); return; }
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(customersProvider.notifier).createCustomer({
        'id': const Uuid().v4(),
        'full_name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        if (_phone2Ctrl.text.trim().isNotEmpty) 'phone2': _phone2Ctrl.text.trim(),
        if (_cityCtrl.text.trim().isNotEmpty) 'city': _cityCtrl.text.trim(),
        if (_areaCtrl.text.trim().isNotEmpty) 'area': _areaCtrl.text.trim(),
        if (_streetCtrl.text.trim().isNotEmpty) 'street': _streetCtrl.text.trim(),
        if (_locationUrlCtrl.text.trim().isNotEmpty) 'location_url': _locationUrlCtrl.text.trim(),
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
        constraints: BoxConstraints(maxWidth: 460, maxHeight: dialogMaxHeight(context)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('إضافة عميل', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white)),
            const SizedBox(height: 24),
            if (_error != null) Container(
              padding: const EdgeInsets.all(10), margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: AppTheme.error.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
              child: Text(_error!, style: const TextStyle(color: AppTheme.error, fontSize: 13)),
            ),
            TextField(controller: _nameCtrl, style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'الاسم الكامل *', prefixIcon: Icon(Icons.person))),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: _phoneCtrl, style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'رقم الهاتف', prefixIcon: Icon(Icons.phone), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: _phone2Ctrl, style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'رقم ثاني', prefixIcon: Icon(Icons.phone_outlined), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)))),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: _cityCtrl, style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'المدينة', prefixIcon: Icon(Icons.location_city), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: _areaCtrl, style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'المنطقة', prefixIcon: Icon(Icons.map_outlined), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)))),
            ]),
            const SizedBox(height: 12),
            TextField(controller: _streetCtrl, style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'الشارع أو العنوان', prefixIcon: Icon(Icons.home_outlined))),
            const SizedBox(height: 12),
            TextField(controller: _locationUrlCtrl, style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'رابط اللوكيشن', hintText: 'https://maps.google.com/...', hintStyle: TextStyle(color: Colors.white24), prefixIcon: Icon(Icons.location_on_outlined))),
            const SizedBox(height: 24),
            SizedBox(height: 48, child: ElevatedButton(
              onPressed: _loading ? null : _create,
              child: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('إضافة العميل'),
            )),
          ]),
        ),
      ),
    );
  }
}

// ─── Edit Customer Dialog ─────────────────────────────────────
class _EditCustomerDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> customer;
  final VoidCallback onUpdated;
  const _EditCustomerDialog({required this.customer, required this.onUpdated});
  @override
  ConsumerState<_EditCustomerDialog> createState() => _EditCustomerDialogState();
}

class _EditCustomerDialogState extends ConsumerState<_EditCustomerDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _phone2Ctrl;
  late final TextEditingController _cityCtrl;
  late final TextEditingController _areaCtrl;
  late final TextEditingController _streetCtrl;
  late final TextEditingController _locationUrlCtrl;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameCtrl        = TextEditingController(text: widget.customer['full_name'] as String? ?? '');
    _phoneCtrl       = TextEditingController(text: widget.customer['phone'] as String? ?? '');
    _phone2Ctrl      = TextEditingController(text: widget.customer['phone2'] as String? ?? '');
    _cityCtrl        = TextEditingController(text: widget.customer['city'] as String? ?? '');
    _areaCtrl        = TextEditingController(text: widget.customer['area'] as String? ?? '');
    _streetCtrl      = TextEditingController(text: widget.customer['street'] as String? ?? '');
    _locationUrlCtrl = TextEditingController(text: widget.customer['location_url'] as String? ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _phoneCtrl.dispose(); _phone2Ctrl.dispose();
    _cityCtrl.dispose(); _areaCtrl.dispose(); _streetCtrl.dispose();
    _locationUrlCtrl.dispose(); super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.isEmpty) { setState(() => _error = 'الاسم مطلوب'); return; }
    setState(() { _loading = true; _error = null; });
    try {
      final id = widget.customer['id'] as String;
      final updates = <String, dynamic>{
        'full_name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'phone2': _phone2Ctrl.text.trim(),
        'city': _cityCtrl.text.trim(),
        'area': _areaCtrl.text.trim(),
        'street': _streetCtrl.text.trim(),
        'location_url': _locationUrlCtrl.text.trim(),
      };
      if (widget.customer['version'] != null) {
        updates['version'] = widget.customer['version'];
      }
      await ref.read(customersProvider.notifier).updateCustomer(id, updates);
      widget.onUpdated();
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تحديث بيانات العميل'), backgroundColor: AppTheme.success));
      }
    } catch (e) { setState(() => _error = e.toString()); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 460, maxHeight: dialogMaxHeight(context)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.edit, color: AppTheme.primary, size: 22),
              ),
              const SizedBox(width: 12),
              const Text('تعديل بيانات العميل', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white)),
            ]),
            const SizedBox(height: 24),
            if (_error != null) Container(
              padding: const EdgeInsets.all(10), margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: AppTheme.error.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
              child: Text(_error!, style: const TextStyle(color: AppTheme.error, fontSize: 13)),
            ),
            TextField(controller: _nameCtrl, style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'الاسم الكامل *', prefixIcon: Icon(Icons.person))),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: _phoneCtrl, style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'رقم الهاتف', prefixIcon: Icon(Icons.phone), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: _phone2Ctrl, style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'رقم ثاني', prefixIcon: Icon(Icons.phone_outlined), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)))),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: _cityCtrl, style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'المدينة', prefixIcon: Icon(Icons.location_city), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: _areaCtrl, style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'المنطقة', prefixIcon: Icon(Icons.map_outlined), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)))),
            ]),
            const SizedBox(height: 12),
            TextField(controller: _streetCtrl, style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'الشارع أو العنوان', prefixIcon: Icon(Icons.home_outlined))),
            const SizedBox(height: 12),
            TextField(controller: _locationUrlCtrl, style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'رابط اللوكيشن', hintText: 'https://maps.google.com/...', hintStyle: TextStyle(color: Colors.white24), prefixIcon: Icon(Icons.location_on_outlined))),
            const SizedBox(height: 24),
            SizedBox(height: 52, child: ElevatedButton.icon(
              onPressed: _loading ? null : _save,
              icon: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save, size: 20),
              label: Text(_loading ? 'جاري الحفظ...' : 'حفظ التعديلات', style: const TextStyle(fontSize: 15)),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
            )),
          ]),
        ),
      ),
    );
  }
}
