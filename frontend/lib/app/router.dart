
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/dashboard/presentation/dashboard_shell.dart';
import '../features/dashboard/presentation/overview_screen.dart';
import '../features/orders/presentation/orders_screen.dart';
import '../features/warehouse/presentation/scanning_screen.dart';
import '../features/shipments/presentation/shipments_screen.dart';
import '../features/customers/presentation/customers_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/login',
    routes: [
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => DashboardShell(child: child),
        routes: [
          GoRoute(
            path: '/',
            name: 'overview',
            builder: (context, state) => const OverviewScreen(),
          ),
          GoRoute(
            path: '/orders',
            name: 'orders',
            builder: (context, state) => const OrdersScreen(),
          ),
          GoRoute(
            path: '/warehouse',
            name: 'warehouse',
            builder: (context, state) => const ScanningScreen(),
          ),
          GoRoute(
            path: '/shipments',
            name: 'shipments',
            builder: (context, state) => const ShipmentsScreen(),
          ),
          GoRoute(
            path: '/customers',
            name: 'customers',
            builder: (context, state) => const CustomersScreen(),
          ),
        ],
      ),
    ],
  );
});
