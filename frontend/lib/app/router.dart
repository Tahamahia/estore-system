import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/auth_service.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/dashboard/presentation/dashboard_shell.dart';
import '../features/dashboard/presentation/overview_screen.dart';
import '../features/orders/presentation/orders_screen.dart';
import '../features/orders/presentation/order_detail_screen.dart';
import '../features/warehouse/presentation/scanning_screen.dart';
import '../features/shipments/presentation/shipments_screen.dart';
import '../features/customers/presentation/customers_screen.dart';
import '../features/browser/in_app_browser_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // Watch auth state for redirects
  final token = ref.watch(authTokenProvider);

  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      final isLoggedIn = token != null;
      final isLoginPage = state.matchedLocation == '/login';

      // Not logged in → force to login (except if already there)
      if (!isLoggedIn && !isLoginPage) return '/login';
      // Logged in → redirect away from login to dashboard
      if (isLoggedIn && isLoginPage) return '/';

      return null; // No redirect needed
    },
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
            path: '/orders/:id',
            name: 'orderDetail',
            builder: (context, state) => OrderDetailScreen(
              orderId: state.pathParameters['id']!,
            ),
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
          GoRoute(
            path: '/browser',
            name: 'browser',
            builder: (context, state) => const InAppBrowserScreen(),
          ),
        ],
      ),
    ],
  );
});
