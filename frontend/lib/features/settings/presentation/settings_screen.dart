import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:estore_app/app/theme.dart';
import 'package:estore_app/core/auth_service.dart';
import 'package:estore_app/core/providers.dart';
import 'package:estore_app/core/utils/dialog_utils.dart';

const _kRoles = [
  MapEntry('super_admin', 'مدير النظام'),
  MapEntry('store_manager', 'مديرة المتجر'),
  MapEntry('purchaser', 'مسؤولة الشراء'),
  MapEntry('sorter', 'موظفة المخزن'),
  MapEntry('driver', 'مندوب'),
];

String _roleLabel(String role) => _kRoles.firstWhere(
  (e) => e.key == role,
  orElse: () => MapEntry(role, role),
).value;

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  List<Map<String, dynamic>>? _pendingRequests;
  bool _pendingError = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(shippingSourcesProvider.notifier).fetchSources();
      final currentUser = ref.read(currentUserProvider);
      if ((currentUser?['role'] as String?) == 'super_admin') {
        ref.read(usersProvider.notifier).fetchUsers();
        _loadPendingRequests();
      }
    });
  }

  Future<void> _loadPendingRequests() async {
    if (mounted) setState(() { _pendingError = false; _pendingRequests = null; });
    try {
      final pending = await ref.read(usersProvider.notifier).fetchPendingRequests();
      if (mounted) setState(() => _pendingRequests = pending);
    } catch (_) {
      if (mounted) setState(() { _pendingRequests = []; _pendingError = true; });
    }
  }

  // ── Shipping Sources ────────────────────────────────────────

  void _showAddDialog() {
    showDialog(context: context, builder: (_) => _SourceDialog(
      onSave: (name, rate) async {
        await ref.read(shippingSourcesProvider.notifier).createSource(name, rate);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('✅ تم إضافة "$name"'),
            backgroundColor: AppTheme.success,
          ));
        }
      },
    ));
  }

  void _showEditDialog(Map<String, dynamic> source) {
    showDialog(context: context, builder: (_) => _SourceDialog(
      initialName: source['name'] as String,
      initialRate: (source['rate_per_kg'] as num).toDouble(),
      onSave: (name, rate) async {
        await ref.read(shippingSourcesProvider.notifier).updateSource(
          (source['id'] as num).toInt(), name, rate,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('✅ تم تحديث "$name"'),
            backgroundColor: AppTheme.success,
          ));
        }
      },
    ));
  }

  void _confirmDelete(Map<String, dynamic> source) {
    final name = source['name'] as String;
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: AppTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('تأكيد الحذف', style: TextStyle(color: Colors.white)),
      content: Text('هل تريد حذف "$name"؟ لا يمكن التراجع عن هذا الإجراء.',
        style: const TextStyle(color: Colors.white70)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
        ),
        ElevatedButton(
          onPressed: () async {
            Navigator.of(context).pop();
            await ref.read(shippingSourcesProvider.notifier).deleteSource(
              (source['id'] as num).toInt(),
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('تم حذف "$name"'),
                backgroundColor: AppTheme.error,
              ));
            }
          },
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
          child: const Text('حذف'),
        ),
      ],
    ));
  }

  // ── User Management ─────────────────────────────────────────

  void _showAddUserDialog() {
    final currentUser = ref.read(currentUserProvider);
    final tenantId = currentUser?['tenant_id'] as String? ?? '';
    showDialog(context: context, builder: (_) => _AddUserDialog(tenantId: tenantId));
  }

  void _showChangeRoleDialog(Map<String, dynamic> user) {
    String selectedRole = user['role'] as String? ?? 'sorter';
    final name = user['full_name'] as String? ?? '';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.darkSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('تغيير دور $name', style: const TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: _kRoles.map((entry) => RadioListTile<String>(
              title: Text(entry.value, style: const TextStyle(color: Colors.white70)),
              value: entry.key,
              groupValue: selectedRole,
              activeColor: AppTheme.primary,
              onChanged: (v) => setDialogState(() => selectedRole = v!),
            )).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                final messenger = ScaffoldMessenger.of(context);
                await ref.read(usersProvider.notifier).updateUser(
                  user['id'] as String,
                  {'role': selectedRole},
                );
                if (mounted) {
                  messenger.showSnackBar(const SnackBar(
                    content: Text('تم تحديث الدور'),
                    backgroundColor: AppTheme.success,
                  ));
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  void _showResetPasswordDialog(Map<String, dynamic> user) {
    showDialog(context: context, builder: (_) => _ResetPasswordDialog(
      userId: user['id'] as String,
      userName: user['full_name'] as String? ?? user['email'] as String,
      onSuccess: () {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('تم إعادة تعيين كلمة المرور'),
            backgroundColor: AppTheme.success,
          ));
        }
      },
    ));
  }

  void _confirmToggleActive(Map<String, dynamic> user) {
    final isActive = (user['is_active'] as int?) != 0;
    final name = user['full_name'] as String? ?? user['email'] as String;
    final action = isActive ? 'تعطيل' : 'تفعيل';
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: AppTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('$action الحساب', style: const TextStyle(color: Colors.white)),
      content: Text('هل تريد $action حساب "$name"؟', style: const TextStyle(color: Colors.white70)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
        ),
        ElevatedButton(
          onPressed: () async {
            Navigator.of(context).pop();
            final messenger = ScaffoldMessenger.of(context);
            await ref.read(usersProvider.notifier).updateUser(
              user['id'] as String,
              {'is_active': isActive ? 0 : 1},
            );
            if (mounted) {
              messenger.showSnackBar(SnackBar(
                content: Text('تم $action الحساب'),
                backgroundColor: isActive ? AppTheme.error : AppTheme.success,
              ));
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: isActive ? AppTheme.error : AppTheme.success,
          ),
          child: Text(action),
        ),
      ],
    ));
  }

  // ── Pending Requests ────────────────────────────────────────

  void _showApproveDialog(Map<String, dynamic> req) {
    final name = req['full_name'] as String? ?? '';
    showDialog(context: context, builder: (_) => _ApproveDialog(
      request: req,
      onApproved: () {
        _loadPendingRequests();
        ref.read(usersProvider.notifier).fetchUsers();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('تمت الموافقة على $name'),
            backgroundColor: AppTheme.success,
          ));
        }
      },
    ));
  }

  void _confirmReject(Map<String, dynamic> req) {
    final name = req['full_name'] as String? ?? '';
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: AppTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('رفض الطلب', style: TextStyle(color: Colors.white)),
      content: Text('هل تريد رفض طلب "$name"؟', style: const TextStyle(color: Colors.white70)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
        ),
        ElevatedButton(
          onPressed: () async {
            final navigator = Navigator.of(context);
            final messenger = ScaffoldMessenger.of(context);
            navigator.pop();
            await ref.read(usersProvider.notifier).rejectUser(req['id'] as String);
            _loadPendingRequests();
            if (mounted) {
              messenger.showSnackBar(const SnackBar(
                content: Text('تم رفض الطلب'),
                backgroundColor: AppTheme.error,
              ));
            }
          },
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
          child: const Text('رفض'),
        ),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final sourcesState = ref.watch(shippingSourcesProvider);
    final currentUser = ref.watch(currentUserProvider);
    final isSuperAdmin = (currentUser?['role'] as String?) == 'super_admin';
    final currentUserId = currentUser?['id'] as String?;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Text('الضبط', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white)),
              const Spacer(),
            ]),
            const SizedBox(height: 24),

            // ── Shipping Sources Section ──────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.darkSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.darkBorder),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.language_outlined, color: AppTheme.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                    Text('مواقع الشراء', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                    Text('سعر الشحن لكل كيلو (\$) بحسب الموقع', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  ]),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: _showAddDialog,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('إضافة موقع'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                sourcesState.when(
                  loading: () => const Center(child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(),
                  )),
                  error: (e, _) => Center(child: Text('فشل تحميل المواقع: $e',
                    style: const TextStyle(color: AppTheme.error))),
                  data: (sources) {
                    if (sources.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('لا توجد مواقع مضافة بعد', style: TextStyle(color: Colors.white38)),
                        ),
                      );
                    }
                    return Column(
                      children: sources.map((source) => _SourceTile(
                        source: source,
                        onEdit: () => _showEditDialog(source),
                        onDelete: () => _confirmDelete(source),
                      )).toList(),
                    );
                  },
                ),
              ]),
            ),

            // ── super_admin only sections ─────────────────────────
            if (isSuperAdmin) ...[
              const SizedBox(height: 24),
              _buildPendingSection(),
              const SizedBox(height: 24),
              _buildUsersSection(currentUserId),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPendingSection() {
    final pending = _pendingRequests;
    final count = pending?.length ?? 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.warning.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.person_search_outlined, color: AppTheme.warning, size: 20),
          ),
          const SizedBox(width: 12),
          Row(children: [
            const Text('طلبات الانضمام', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
            if (count > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.warning,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ],
          ]),
        ]),
        const SizedBox(height: 4),
        const Padding(
          padding: EdgeInsets.only(right: 4),
          child: Text('طلبات الانضمام الجديدة التي تحتاج مراجعة', style: TextStyle(color: Colors.white54, fontSize: 12)),
        ),
        const SizedBox(height: 16),
        if (pending == null && !_pendingError)
          const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
        else if (_pendingError)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.error.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.error.withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.error_outline, color: AppTheme.error, size: 20),
              const SizedBox(width: 8),
              const Expanded(child: Text('فشل تحميل الطلبات', style: TextStyle(color: AppTheme.error))),
              TextButton(
                onPressed: _loadPendingRequests,
                child: const Text('إعادة المحاولة', style: TextStyle(color: AppTheme.primary)),
              ),
            ]),
          )
        else if (pending!.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(
              child: Text('لا توجد طلبات انضمام جديدة ✓', style: TextStyle(color: Colors.white38)),
            ),
          )
        else
          Column(
            children: pending.map((req) => _PendingRequestTile(
              request: req,
              onApprove: () => _showApproveDialog(req),
              onReject: () => _confirmReject(req),
            )).toList(),
          ),
      ]),
    );
  }

  Widget _buildUsersSection(String? currentUserId) {
    final usersState = ref.watch(usersProvider);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.group_outlined, color: AppTheme.accent, size: 20),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
            Text('إدارة المستخدمين', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
            Text('إضافة وإدارة موظفي المتجر', style: TextStyle(color: Colors.white54, fontSize: 12)),
          ]),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: _showAddUserDialog,
            icon: const Icon(Icons.person_add_outlined, size: 18),
            label: const Text('إضافة موظف'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accent,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        usersState.when(
          loading: () => const Center(child: Padding(
            padding: EdgeInsets.all(20),
            child: CircularProgressIndicator(),
          )),
          error: (e, _) => Center(child: Text('فشل تحميل المستخدمين: $e',
            style: const TextStyle(color: AppTheme.error))),
          data: (users) {
            if (users.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('لا يوجد مستخدمون', style: TextStyle(color: Colors.white38)),
                ),
              );
            }
            return Column(
              children: users.map((user) {
                final userId = user['id'] as String;
                final isSelf = userId == currentUserId;
                return _UserTile(
                  user: user,
                  isSelf: isSelf,
                  onChangeRole: isSelf ? null : () => _showChangeRoleDialog(user),
                  onResetPassword: isSelf ? null : () => _showResetPasswordDialog(user),
                  onToggleActive: isSelf ? null : () => _confirmToggleActive(user),
                );
              }).toList(),
            );
          },
        ),
      ]),
    );
  }
}

class _UserTile extends StatelessWidget {
  final Map<String, dynamic> user;
  final bool isSelf;
  final VoidCallback? onChangeRole;
  final VoidCallback? onResetPassword;
  final VoidCallback? onToggleActive;
  const _UserTile({
    required this.user,
    required this.isSelf,
    this.onChangeRole,
    this.onResetPassword,
    this.onToggleActive,
  });

  @override
  Widget build(BuildContext context) {
    final name = user['full_name'] as String? ?? '';
    final email = user['email'] as String? ?? '';
    final role = user['role'] as String? ?? '';
    final isActive = (user['is_active'] as int?) != 0;
    final label = _roleLabel(role);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: (isActive ? AppTheme.accent : Colors.grey).withValues(alpha: 0.2),
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: TextStyle(
              color: isActive ? AppTheme.accent : Colors.grey,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
            if (isSelf) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('أنت', style: TextStyle(color: AppTheme.primary, fontSize: 10)),
              ),
            ],
          ]),
          Text(email, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ])),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.secondary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(label, style: const TextStyle(color: AppTheme.secondary, fontSize: 11)),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: (isActive ? AppTheme.success : AppTheme.error).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            isActive ? 'نشط' : 'معطل',
            style: TextStyle(color: isActive ? AppTheme.success : AppTheme.error, fontSize: 11),
          ),
        ),
        if (!isSelf) ...[
          IconButton(
            icon: const Icon(Icons.manage_accounts_outlined, color: Colors.white54, size: 20),
            onPressed: onChangeRole,
            tooltip: 'تغيير الدور',
          ),
          IconButton(
            icon: const Icon(Icons.password_outlined, color: Colors.white54, size: 20),
            onPressed: onResetPassword,
            tooltip: 'إعادة تعيين كلمة المرور',
          ),
          IconButton(
            icon: Icon(
              isActive ? Icons.block_outlined : Icons.check_circle_outline,
              color: isActive ? AppTheme.error : AppTheme.success,
              size: 20,
            ),
            onPressed: onToggleActive,
            tooltip: isActive ? 'تعطيل' : 'تفعيل',
          ),
        ],
      ]),
    );
  }
}

class _SourceTile extends StatelessWidget {
  final Map<String, dynamic> source;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _SourceTile({required this.source, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final name = source['name'] as String;
    final rate = (source['rate_per_kg'] as num).toDouble();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.secondary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.storefront_outlined, color: AppTheme.secondary, size: 18),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
          Text('\$${rate.toStringAsFixed(2)} / كيلو', style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ])),
        IconButton(
          icon: const Icon(Icons.edit_outlined, color: Colors.white54, size: 20),
          onPressed: onEdit,
          tooltip: 'تعديل',
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline, color: AppTheme.error, size: 20),
          onPressed: onDelete,
          tooltip: 'حذف',
        ),
      ]),
    );
  }
}

class _SourceDialog extends StatefulWidget {
  final String? initialName;
  final double? initialRate;
  final Future<void> Function(String name, double rate) onSave;
  const _SourceDialog({this.initialName, this.initialRate, required this.onSave});

  @override
  State<_SourceDialog> createState() => _SourceDialogState();
}

class _SourceDialogState extends State<_SourceDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _rateCtrl;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName ?? '');
    _rateCtrl = TextEditingController(
      text: widget.initialRate != null ? widget.initialRate!.toString() : '',
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _rateCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initialName != null;

    return Dialog(
      backgroundColor: AppTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              isEdit ? 'تعديل موقع الشراء' : 'إضافة موقع شراء',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
            ),
            const SizedBox(height: 20),
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: AppTheme.error.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                child: Text(_error!, style: const TextStyle(color: AppTheme.error, fontSize: 13)),
              ),
            ],
            TextField(
              controller: _nameCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'اسم الموقع *',
                hintText: 'مثال: Shein',
                hintStyle: TextStyle(color: Colors.white24),
                prefixIcon: Icon(Icons.language_outlined),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _rateCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'سعر الشحن للكيلو (\$) *',
                hintText: 'مثال: 8.5',
                hintStyle: TextStyle(color: Colors.white24),
                prefixIcon: Icon(Icons.scale_outlined),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(height: 48, child: ElevatedButton.icon(
              onPressed: _saving ? null : () async {
                final name = _nameCtrl.text.trim();
                final rate = double.tryParse(_rateCtrl.text.trim());
                if (name.isEmpty) { setState(() => _error = 'اسم الموقع مطلوب'); return; }
                if (rate == null || rate < 0) { setState(() => _error = 'سعر الشحن يجب أن يكون رقماً موجباً'); return; }
                setState(() { _saving = true; _error = null; });
                final navigator = Navigator.of(context);
                await widget.onSave(name, rate);
                if (mounted) navigator.pop();
              },
              icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_rounded, size: 20),
              label: Text(_saving ? 'جاري الحفظ...' : (isEdit ? 'حفظ التغييرات' : 'إضافة')),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            )),
          ]),
        ),
      ),
    );
  }
}

class _AddUserDialog extends ConsumerStatefulWidget {
  final String tenantId;
  const _AddUserDialog({required this.tenantId});

  @override
  ConsumerState<_AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends ConsumerState<_AddUserDialog> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  String _selectedRole = 'sorter';
  bool _obscure = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('إضافة موظف جديد',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 20),
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppTheme.error.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_error!, style: const TextStyle(color: AppTheme.error, fontSize: 13)),
              ),
            ],
            TextField(
              controller: _nameCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'الاسم الكامل *',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'البريد الإلكتروني *',
                prefixIcon: Icon(Icons.email_outlined),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _passwordCtrl,
              obscureText: _obscure,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'كلمة المرور (8+ أحرف) *',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: _selectedRole,
              dropdownColor: AppTheme.darkCard,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'الدور *',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              items: _kRoles.map((e) => DropdownMenuItem(
                value: e.key,
                child: Text(e.value),
              )).toList(),
              onChanged: (v) => setState(() => _selectedRole = v!),
            ),
            const SizedBox(height: 24),
            SizedBox(height: 48, child: ElevatedButton.icon(
              onPressed: _saving ? null : () async {
                final name = _nameCtrl.text.trim();
                final email = _emailCtrl.text.trim();
                final password = _passwordCtrl.text;
                if (name.isEmpty || email.isEmpty || password.isEmpty) {
                  setState(() => _error = 'جميع الحقول مطلوبة');
                  return;
                }
                if (password.length < 8) {
                  setState(() => _error = 'كلمة المرور يجب أن تكون 8 أحرف على الأقل');
                  return;
                }
                setState(() { _saving = true; _error = null; });
                final navigator = Navigator.of(context);
                try {
                  await ref.read(usersProvider.notifier).createUser({
                    'id': const Uuid().v4(),
                    'email': email,
                    'password': password,
                    'full_name': name,
                    'tenant_id': widget.tenantId,
                    'role': _selectedRole,
                  });
                  if (mounted) navigator.pop();
                } on DioException catch (e) {
                  final data = e.response?.data;
                  final msg = data is Map
                      ? (data['message'] as String? ?? 'فشل إضافة المستخدم')
                      : 'فشل إضافة المستخدم';
                  setState(() { _error = msg; _saving = false; });
                } catch (e) {
                  setState(() { _error = 'فشل إضافة المستخدم: $e'; _saving = false; });
                }
              },
              icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.person_add_outlined, size: 20),
              label: Text(_saving ? 'جاري الإضافة...' : 'إضافة'),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
            )),
          ]),
        ),
      ),
    );
  }
}

class _ResetPasswordDialog extends ConsumerStatefulWidget {
  final String userId;
  final String userName;
  final VoidCallback? onSuccess;
  const _ResetPasswordDialog({required this.userId, required this.userName, this.onSuccess});

  @override
  ConsumerState<_ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends ConsumerState<_ResetPasswordDialog> {
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              'إعادة تعيين كلمة مرور\n${widget.userName}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
            ),
            const SizedBox(height: 20),
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppTheme.error.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_error!, style: const TextStyle(color: AppTheme.error, fontSize: 13)),
              ),
            ],
            TextField(
              controller: _passwordCtrl,
              obscureText: _obscure,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'كلمة المرور الجديدة (8+ أحرف)',
                prefixIcon: const Icon(Icons.lock_reset_outlined),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(child: TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
              )),
              const SizedBox(width: 12),
              Expanded(child: SizedBox(height: 48, child: ElevatedButton(
                onPressed: _saving ? null : () async {
                  final password = _passwordCtrl.text;
                  if (password.length < 8) {
                    setState(() => _error = 'كلمة المرور يجب أن تكون 8 أحرف على الأقل');
                    return;
                  }
                  setState(() { _saving = true; _error = null; });
                  final navigator = Navigator.of(context);
                  try {
                    await ref.read(usersProvider.notifier).resetPassword(widget.userId, password);
                    if (mounted) {
                      navigator.pop();
                      widget.onSuccess?.call();
                    }
                  } on DioException catch (e) {
                    final data = e.response?.data;
                    final msg = data is Map
                        ? (data['message'] as String? ?? 'فشل إعادة تعيين كلمة المرور')
                        : 'فشل إعادة تعيين كلمة المرور';
                    setState(() { _error = msg; _saving = false; });
                  } catch (e) {
                    setState(() { _error = 'فشل إعادة تعيين كلمة المرور'; _saving = false; });
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.warning),
                child: _saving
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : const Text('تعيين', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ))),
            ]),
          ]),
        ),
      ),
    );
  }
}

String _formatDate(String? dateStr) {
  if (dateStr == null) return '';
  final dt = DateTime.tryParse(dateStr);
  if (dt == null) return dateStr;
  return '${dt.day}/${dt.month}/${dt.year}';
}

class _PendingRequestTile extends StatelessWidget {
  final Map<String, dynamic> request;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  const _PendingRequestTile({required this.request, required this.onApprove, required this.onReject});

  @override
  Widget build(BuildContext context) {
    final name = request['full_name'] as String? ?? '';
    final email = request['email'] as String? ?? '';
    final createdAt = request['created_at'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: AppTheme.warning.withValues(alpha: 0.2),
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: const TextStyle(color: AppTheme.warning, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
          Text(email, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          if (createdAt != null)
            Text(_formatDate(createdAt), style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ])),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: onApprove,
          icon: const Icon(Icons.check_rounded, size: 16),
          label: const Text('قبول'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.success,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            textStyle: const TextStyle(fontSize: 12),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: onReject,
          icon: const Icon(Icons.close_rounded, size: 16),
          label: const Text('رفض'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.error,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            textStyle: const TextStyle(fontSize: 12),
          ),
        ),
      ]),
    );
  }
}

class _ApproveDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> request;
  final VoidCallback onApproved;
  const _ApproveDialog({required this.request, required this.onApproved});

  @override
  ConsumerState<_ApproveDialog> createState() => _ApproveDialogState();
}

class _ApproveDialogState extends ConsumerState<_ApproveDialog> {
  String _selectedRole = 'sorter';
  bool _saving = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final name = widget.request['full_name'] as String? ?? '';

    return Dialog(
      backgroundColor: AppTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 400, maxHeight: dialogMaxHeight(context)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('قبول طلب $name',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 20),
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppTheme.error.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_error!, style: const TextStyle(color: AppTheme.error, fontSize: 13)),
              ),
            ],
            DropdownButtonFormField<String>(
              value: _selectedRole,
              dropdownColor: AppTheme.darkCard,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'الدور',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              items: _kRoles.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
              onChanged: (v) => setState(() => _selectedRole = v!),
            ),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(child: TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
              )),
              const SizedBox(width: 12),
              Expanded(child: SizedBox(height: 48, child: ElevatedButton(
                onPressed: _saving ? null : () async {
                  setState(() { _saving = true; _error = null; });
                  final navigator = Navigator.of(context);
                  try {
                    await ref.read(usersProvider.notifier).approveUser(
                      widget.request['id'] as String, _selectedRole,
                    );
                    if (mounted) {
                      navigator.pop();
                      widget.onApproved();
                    }
                  } on DioException catch (e) {
                    final data = e.response?.data;
                    final msg = data is Map ? (data['message'] as String? ?? 'فشل القبول') : 'فشل القبول';
                    setState(() { _error = msg; _saving = false; });
                  } catch (e) {
                    setState(() { _error = 'فشل القبول'; _saving = false; });
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
                child: _saving
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : const Text('تأكيد القبول', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ))),
            ]),
          ]),
        ),
      ),
    );
  }
}
