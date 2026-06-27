import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/router.dart';
import 'app/theme.dart';
import 'core/sentry.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Sentry — safe no-op if DSN is missing
  await AppSentry.init(
    dsn: const String.fromEnvironment('SENTRY_DSN', defaultValue: ''),
  );

  runApp(const ProviderScope(child: EstoreApp()));
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
