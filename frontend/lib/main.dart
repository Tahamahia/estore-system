import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/router.dart';
import 'app/theme.dart';
import 'core/sentry.dart';
import 'core/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Sentry — safe no-op if DSN is missing
  await AppSentry.init(
    dsn: const String.fromEnvironment('SENTRY_DSN', defaultValue: ''),
  );

  // Create ProviderContainer to load saved auth token before building UI
  final container = ProviderContainer();
  await AuthService.loadSavedToken(container);

  runApp(UncontrolledProviderScope(container: container, child: const EstoreApp()));
}

class EstoreApp extends ConsumerWidget {
  const EstoreApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'eStore Fulfillment System',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      routerConfig: router,
    );
  }
}
