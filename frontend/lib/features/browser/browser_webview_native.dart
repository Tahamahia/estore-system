/// Native platform implementation (Windows/macOS/Android/iOS).
/// Uses webview_flutter to render a real in-app browser.

import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

// Module-level controller — initialized lazily by buildWebView
WebViewController? _controller;

/// Builds the WebViewWidget for native platforms
Widget buildWebView({
  required String initialUrl,
  required void Function(String url) onUrlChanged,
}) {
  _controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: (url) => onUrlChanged(url),
        onPageFinished: (url) => onUrlChanged(url),
        onNavigationRequest: (request) {
          // Allow all navigation (Shein, Trendyol, etc.)
          return NavigationDecision.navigate;
        },
      ),
    )
    ..loadRequest(Uri.parse(initialUrl));

  return WebViewWidget(controller: _controller!);
}

/// Navigate to a URL
void navigateTo(String url) {
  if (_controller == null) return;
  String finalUrl = url.trim();
  if (!finalUrl.startsWith('http://') && !finalUrl.startsWith('https://')) {
    finalUrl = 'https://$finalUrl';
  }
  _controller!.loadRequest(Uri.parse(finalUrl));
}

/// Go back in history
void goBack() => _controller?.goBack();

/// Go forward in history
void goForward() => _controller?.goForward();

/// Reload the page
void reload() => _controller?.reload();

/// Execute JavaScript and return the result string
Future<String?> runExtractionJs(String js) async {
  if (_controller == null) return null;
  final result = await _controller!.runJavaScriptReturningResult(js);
  return result.toString();
}
