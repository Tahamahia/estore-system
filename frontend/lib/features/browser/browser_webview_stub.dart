/// Stub implementation for Web platform.
/// All WebView functions are no-ops on Web since webview_flutter
/// cannot render inside a browser.

import 'package:flutter/widgets.dart';

/// Builds a placeholder widget (never called on web due to kIsWeb guard)
Widget buildWebView({
  required String initialUrl,
  required void Function(String url) onUrlChanged,
}) {
  return const Center(child: Text('WebView not available on web'));
}

/// No-op navigation stubs
void navigateTo(String url) {}
void goBack() {}
void goForward() {}
void reload() {}

/// No-op extraction
Future<String?> runExtractionJs(String js) async => null;
