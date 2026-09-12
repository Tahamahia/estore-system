import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/auth_service.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/signup_screen.dart';
import '../features/dashboard/presentation/dashboard_shell.dart';
import '../features/dashboard/presentation/overview_screen.dart';
import '../features/orders/presentation/orders_screen.dart';
import '../features/orders/presentation/order_detail_screen.dart';
import '../features/warehouse/presentation/scanning_screen.dart';
import '../features/logistics/presentation/external_shipments_screen.dart';
import '../features/logistics/presentation/internal_shipments_screen.dart';
import '../features/customers/presentation/customers_screen.dart';
import '../features/settlements/presentation/settlements_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/inventory/presentation/in_stock_screen.dart';
import '../features/purchasing/presentation/purchasing_screen.dart';
import '../features/driver/presentation/driver_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // Watch auth state for redirects
  final token = ref.watch(authTokenProvider);

  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      final isLoggedIn = token != null;
      final location = state.matchedLocation;
      final isPublicPage = location == '/login' || location == '/signup';

      if (!isLoggedIn && !isPublicPage) return '/login';
      if (isLoggedIn && isPublicPage) {
        final role = ref.read(currentUserProvider)?['role'] as String?;
        switch (role) {
          case 'sorter':
            return '/warehouse';
          case 'driver':
            return '/driver';
          default:
            return '/';
        }
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/signup',
        name: 'signup',
        builder: (context, state) => const SignupScreen(),
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
            path: '/purchasing',
            name: 'purchasing',
            builder: (context, state) => const PurchasingScreen(),
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
            path: '/external-shipments',
            name: 'externalShipments',
            builder: (context, state) => const ExternalShipmentsScreen(),
          ),
          GoRoute(
            path: '/internal-shipments',
            name: 'internalShipments',
            builder: (context, state) => const InternalShipmentsScreen(),
          ),
          GoRoute(
            path: '/customers',
            name: 'customers',
            builder: (context, state) => const CustomersScreen(),
          ),
          GoRoute(
            path: '/settlements',
            name: 'settlements',
            builder: (context, state) => const SettlementsScreen(),
          ),
          GoRoute(
            path: '/settings',
            name: 'settings',
            builder: (context, state) => const SettingsScreen(),
          ),
          GoRoute(
            path: '/in-stock',
            name: 'inStock',
            builder: (context, state) => const InStockScreen(),
          ),
          GoRoute(
            path: '/driver',
            name: 'driver',
            builder: (context, state) => const DriverScreen(),
          ),
        ],
      ),
    ],
  );
});
