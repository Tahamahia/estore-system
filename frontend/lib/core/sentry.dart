import 'package:flutter/foundation.dart';

/// Sentry Error Tracking Scaffolding for Flutter Web
///
/// SAFE: If SENTRY_DSN is empty/null/missing, all calls are no-ops.
/// The app runs perfectly without Sentry configured.
///
/// To enable Sentry in production:
/// 1. Add `sentry_flutter: ^8.0.0` to pubspec.yaml
/// 2. Set the DSN in your deployment environment
/// 3. Uncomment the SentryFlutter.init() call in main.dart
///
/// For now, we use a lightweight wrapper that logs to console in debug
/// and silently discards in release mode.

class AppSentry {
  static String? _dsn;
  static bool _initialized = false;

  /// Initialize Sentry with an optional DSN.
  /// If DSN is null/empty, Sentry becomes a safe no-op.
  static Future<void> init({String? dsn}) async {
    _dsn = dsn;

    if (dsn == null || dsn.trim().isEmpty) {
      if (kDebugMode) {
        print('[Sentry] DSN not configured — running in no-op mode');
      }
      return;
    }

    // When sentry_flutter is added to pubspec.yaml, uncomment:
    // await SentryFlutter.init(
    //   (options) {
    //     options.dsn = dsn;
    //     options.tracesSampleRate = 0.2;
    //     options.environment = kDebugMode ? 'development' : 'production';
    //   },
    // );

    _initialized = true;
    if (kDebugMode) {
      print('[Sentry] Initialized with DSN: ${dsn.substring(0, 20)}...');
    }
  }

  /// Capture an exception. No-op if Sentry is not initialized.
  static void captureException(dynamic exception, {dynamic stackTrace}) {
    if (!_initialized) {
      if (kDebugMode) {
        print('[Sentry:NoOp] Exception: $exception');
      }
      return;
    }

    // When sentry_flutter is active:
    // Sentry.captureException(exception, stackTrace: stackTrace);
    if (kDebugMode) {
      print('[Sentry] Captured: $exception');
    }
  }

  /// Capture a message. No-op if Sentry is not initialized.
  static void captureMessage(String message) {
    if (!_initialized) return;
    // Sentry.captureMessage(message);
  }

  /// Add a breadcrumb for context. No-op if not initialized.
  static void addBreadcrumb(String message, {String? category}) {
    if (!_initialized) return;
    // Sentry.addBreadcrumb(Breadcrumb(message: message, category: category));
  }

  /// Check if Sentry is actively tracking
  static bool get isEnabled => _initialized && _dsn != null;
}
