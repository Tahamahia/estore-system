import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:estore_app/app/theme.dart';

class DashboardShell extends StatefulWidget {
  final Widget child;
  const DashboardShell({super.key, required this.child});

  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell> {
  bool _isExpanded = true;

  int _selectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    if (location.startsWith('/orders')) return 1;
    if (location.startsWith('/warehouse')) return 2;
    if (location.startsWith('/shipments')) return 3;
    if (location.startsWith('/customers')) return 4;
    if (location.startsWith('/browser')) return 5;
    return 0;
  }

  static const _navItems = [
    _NavItem(icon: Icons.dashboard_rounded, label: 'Overview', path: '/'),
    _NavItem(icon: Icons.receipt_long_rounded, label: 'Orders', path: '/orders'),
    _NavItem(icon: Icons.qr_code_scanner_rounded, label: 'Warehouse', path: '/warehouse'),
    _NavItem(icon: Icons.local_shipping_rounded, label: 'Shipments', path: '/shipments'),
    _NavItem(icon: Icons.people_rounded, label: 'Customers', path: '/customers'),
    _NavItem(icon: Icons.language_rounded, label: 'Store Browser', path: '/browser'),
  ];

  @override
  Widget build(BuildContext context) {
    final selected = _selectedIndex(context);
    final isWide = MediaQuery.of(context).size.width > 800;

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
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [AppTheme.primary, AppTheme.secondary]),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.warehouse_rounded, size: 24, color: Colors.white),
                      ),
                      if (isWide && _isExpanded) ...[
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'eStore',
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
                        onPressed: () {},
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.darkCard,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: AppTheme.primary,
                              child: Text('A', style: TextStyle(fontSize: 12, color: Colors.white)),
                            ),
                            SizedBox(width: 8),
                            Text('Admin', style: TextStyle(color: Colors.white70, fontSize: 13)),
                          ],
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
