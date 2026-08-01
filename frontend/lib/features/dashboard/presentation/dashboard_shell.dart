import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:estore_app/app/theme.dart';
import 'package:estore_app/core/auth_service.dart';
import 'package:estore_app/core/api_client.dart';
import 'package:estore_app/core/providers.dart';
import 'package:estore_app/core/utils/dialog_utils.dart';

class DashboardShell extends ConsumerStatefulWidget {
  final Widget child;
  const DashboardShell({super.key, required this.child});

  @override
  ConsumerState<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends ConsumerState<DashboardShell> {
  bool _isExpanded = true;

  int _selectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    if (location.startsWith('/orders')) return 1;
    if (location.startsWith('/warehouse')) return 2;
    if (location.startsWith('/external-shipments')) return 3;
    if (location.startsWith('/internal-shipments')) return 4;
    if (location.startsWith('/customers')) return 5;
    if (location.startsWith('/settlements')) return 6;
    if (location.startsWith('/settings')) return 7;
    if (location.startsWith('/in-stock')) return 8;
    return 0;
  }

  static const _navItems = [
    _NavItem(icon: Icons.dashboard_rounded, label: 'Overview', path: '/'),
    _NavItem(icon: Icons.receipt_long_rounded, label: 'Orders', path: '/orders'),
    _NavItem(icon: Icons.qr_code_scanner_rounded, label: 'Warehouse', path: '/warehouse'),
    _NavItem(icon: Icons.flight_land_rounded, label: 'الشحنات الخارجية', path: '/external-shipments'),
    _NavItem(icon: Icons.local_shipping_rounded, label: 'الشحنات الداخلية', path: '/internal-shipments'),
    _NavItem(icon: Icons.people_rounded, label: 'Customers', path: '/customers'),
    _NavItem(icon: Icons.account_balance_wallet_rounded, label: 'التسويات', path: '/settlements'),
    _NavItem(icon: Icons.settings_rounded, label: 'الضبط', path: '/settings'),
    _NavItem(icon: Icons.inventory_2_rounded, label: 'البضاعة الفورية', path: '/in-stock'),
  ];

  Future<void> _handleLogout() async {
    final authService = ref.read(authServiceProvider);
    await authService.logout();
    if (mounted) context.go('/login');
  }

  void _showChangePasswordDialog(BuildContext context) {
    showDialog(context: context, builder: (_) => _ChangePasswordDialog(
      onSuccess: () {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('تم تغيير كلمة المرور بنجاح'),
            backgroundColor: AppTheme.success,
          ));
        }
      },
    ));
  }

  void _showNotifications(BuildContext context) {
    final dashData = ref.read(dashboardProvider);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.darkSurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),
          const Text('📋 Notifications', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          dashData.when(
            loading: () => const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator())),
            error: (_, __) => const _NotifRow(icon: Icons.error_outline, color: AppTheme.error, label: 'Could not load data', value: '—'),
            data: (data) {
              final needsSorting = (data['items_needing_sorting'] as num?)?.toInt() ?? (data['unsorted_items'] as num?)?.toInt() ?? 0;
              final readyDispatch = (data['items_ready_dispatch'] as num?)?.toInt() ?? (data['ready_items'] as num?)?.toInt() ?? 0;
              final totalOrders = (data['total_orders'] as num?)?.toInt() ?? (data['orders_count'] as num?)?.toInt() ?? 0;
              final pendingOrders = (data['pending_orders'] as num?)?.toInt() ?? 0;
              return Column(children: [
                _NotifRow(icon: Icons.sort_rounded, color: AppTheme.warning, label: 'Items needing sorting', value: '$needsSorting'),
                const SizedBox(height: 12),
                _NotifRow(icon: Icons.check_circle_outline, color: AppTheme.success, label: 'Ready for dispatch', value: '$readyDispatch'),
                const SizedBox(height: 12),
                _NotifRow(icon: Icons.receipt_long, color: AppTheme.primary, label: 'Total orders', value: '$totalOrders'),
                const SizedBox(height: 12),
                _NotifRow(icon: Icons.pending_actions, color: AppTheme.accent, label: 'Pending orders', value: '$pendingOrders'),
              ]);
            },
          ),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedIndex(context);
    final isWide = MediaQuery.of(context).size.width > 800;

    // Read user info from provider
    final user = ref.watch(currentUserProvider);
    final userName = (user?['full_name'] as String?) ??
        (user?['email'] as String?) ??
        'User';
    final userInitial = userName.isNotEmpty ? userName[0].toUpperCase() : 'U';

    return Scaffold(
      body: Row(
        children: [
          // Side Navigation
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: isWide ? (_isExpanded ? 240 : 72) : 72,
            decoration: BoxDecoration(
              color: AppTheme.darkSurface,
              border: const Border(right: BorderSide(color: AppTheme.darkBorder)),
            ),
            child: Column(
              children: [
                // Header
                Container(
                  height: 72,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Container(
                        width: 36, height: 36,
                        decoration: const BoxDecoration(color: Color(0xFF6B1A2A), shape: BoxShape.circle),
                        child: ClipOval(child: Image.asset(
                          'assets/images/mukhmal-logo.png',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Text('م', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                          ),
                        )),
                      ),
                      if (isWide && _isExpanded) ...[
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'مخمل',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Divider(height: 1),
                const SizedBox(height: 8),

                // Nav Items
                Expanded(
                  child: ListView.builder(
                    itemCount: _navItems.length,
                    itemBuilder: (context, index) {
                      final item = _navItems[index];
                      final isSelected = index == selected;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => context.go(item.path),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              decoration: BoxDecoration(
                                color: isSelected ? AppTheme.primary.withValues(alpha: 0.15) : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                border: isSelected
                                    ? Border.all(color: AppTheme.primary.withValues(alpha: 0.3))
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    item.icon,
                                    size: 22,
                                    color: isSelected ? AppTheme.primary : Colors.white54,
                                  ),
                                  if (isWide && _isExpanded) ...[
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        item.label,
                                        style: TextStyle(
                                          color: isSelected ? Colors.white : Colors.white70,
                                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // Expand toggle
                if (isWide)
                  IconButton(
                    icon: Icon(
                      _isExpanded ? Icons.chevron_left : Icons.chevron_right,
                      color: Colors.white54,
                    ),
                    onPressed: () => setState(() => _isExpanded = !_isExpanded),
                  ),
                const SizedBox(height: 12),
              ],
            ),
          ),

          // Main Content
          Expanded(
            child: Column(
              children: [
                // Top Bar
                Container(
                  height: 72,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: const BoxDecoration(
                    color: AppTheme.darkSurface,
                    border: Border(bottom: BorderSide(color: AppTheme.darkBorder)),
                  ),
                  child: Row(
                    children: [
                      Text(
                        _navItems[selected].label,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.notifications_outlined, color: Colors.white54),
                        onPressed: () => _showNotifications(context),
                      ),
                      const SizedBox(width: 8),
                      PopupMenuButton<String>(
                        offset: const Offset(0, 50),
                        color: AppTheme.darkCard,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        onSelected: (value) {
                          if (value == 'logout') _handleLogout();
                          if (value == 'change_password') _showChangePasswordDialog(context);
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            enabled: false,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(userName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                                if (user?['email'] != null)
                                  Text(user!['email'] as String, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                              ],
                            ),
                          ),
                          const PopupMenuDivider(),
                          const PopupMenuItem(
                            value: 'change_password',
                            child: Row(
                              children: [
                                Icon(Icons.lock_outline_rounded, color: Colors.white70, size: 20),
                                SizedBox(width: 10),
                                Text('تغيير كلمة المرور', style: TextStyle(color: Colors.white70)),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'logout',
                            child: Row(
                              children: [
                                Icon(Icons.logout_rounded, color: AppTheme.error, size: 20),
                                SizedBox(width: 10),
                                Text('تسجيل الخروج', style: TextStyle(color: AppTheme.error)),
                              ],
                            ),
                          ),
                        ],
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.darkCard,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: AppTheme.primary,
                                child: Text(userInitial, style: const TextStyle(fontSize: 12, color: Colors.white)),
                              ),
                              const SizedBox(width: 8),
                              Text(userName, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                              const SizedBox(width: 4),
                              const Icon(Icons.arrow_drop_down, color: Colors.white54, size: 20),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Page Content
                Expanded(
                  child: widget.child,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final String path;
  const _NavItem({required this.icon, required this.label, required this.path});
}

class _NotifRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  const _NotifRow({required this.icon, required this.color, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500))),
        Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _ChangePasswordDialog extends ConsumerStatefulWidget {
  final VoidCallback onSuccess;
  const _ChangePasswordDialog({required this.onSuccess});

  @override
  ConsumerState<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<_ChangePasswordDialog> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final current = _currentCtrl.text;
    final newPw = _newCtrl.text;
    final confirm = _confirmCtrl.text;

    if (current.isEmpty || newPw.isEmpty || confirm.isEmpty) {
      setState(() => _error = 'يرجى ملء جميع الحقول');
      return;
    }
    if (newPw.length < 8) {
      setState(() => _error = 'كلمة المرور الجديدة يجب أن تكون 8 أحرف على الأقل');
      return;
    }
    if (newPw != confirm) {
      setState(() => _error = 'كلمتا المرور غير متطابقتان');
      return;
    }

    setState(() { _saving = true; _error = null; });
    try {
      await changePassword(ref.read(dioProvider), current, newPw);
      if (mounted) {
        Navigator.of(context).pop();
        widget.onSuccess();
      }
    } on Exception catch (e) {
      // Extract the message from DioException or any other exception
      final msg = e.toString().replaceFirst('DioException [bad response]: ', '');
      setState(() { _error = msg; _saving = false; });
    } catch (e) {
      setState(() { _error = 'فشل تغيير كلمة المرور'; _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 420, maxHeight: dialogMaxHeight(context)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('تغيير كلمة المرور',
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
              controller: _currentCtrl,
              obscureText: _obscureCurrent,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'كلمة المرور الحالية',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_obscureCurrent ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscureCurrent = !_obscureCurrent),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _newCtrl,
              obscureText: _obscureNew,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'كلمة المرور الجديدة',
                prefixIcon: const Icon(Icons.lock_reset_outlined),
                suffixIcon: IconButton(
                  icon: Icon(_obscureNew ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscureNew = !_obscureNew),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _confirmCtrl,
              obscureText: _obscureConfirm,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'تأكيد كلمة المرور الجديدة',
                prefixIcon: const Icon(Icons.lock_reset_outlined),
                suffixIcon: IconButton(
                  icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
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
                onPressed: _saving ? null : _submit,
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                child: _saving
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : const Text('تغيير', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ))),
            ]),
          ]),
        ),
      ),
    );
  }
}
