import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:estore_app/app/theme.dart';
import 'package:estore_app/core/providers.dart';
import 'extraction_js.dart';

// Conditional import: WebView is only available on native platforms
import 'browser_webview_stub.dart'
    if (dart.library.io) 'browser_webview_native.dart';

/// In-App Browser for sourcing products from Shein/Trendyol.
///
/// On native platforms (Windows/macOS/mobile): renders a full WebView
/// with address bar, navigation controls, and cart extraction.
///
/// On Web platform: shows a graceful fallback message since browsers
/// block cross-origin iframe embedding via X-Frame-Options.
class InAppBrowserScreen extends ConsumerStatefulWidget {
  const InAppBrowserScreen({super.key});

  @override
  ConsumerState<InAppBrowserScreen> createState() => _InAppBrowserScreenState();
}

class _InAppBrowserScreenState extends ConsumerState<InAppBrowserScreen> {
  final _urlController = TextEditingController(text: 'https://www.shein.com/cart');
  bool _isExtracting = false;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ── Web Platform Fallback ──
    if (kIsWeb) {
      return _buildWebFallback();
    }

    // ── Native Platform: Full WebView ──
    return _buildNativeBrowser();
  }

  // ─── WEB FALLBACK ─────────────────────────────────────
  Widget _buildWebFallback() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(40),
        padding: const EdgeInsets.all(48),
        constraints: const BoxConstraints(maxWidth: 560),
        decoration: BoxDecoration(
          color: AppTheme.darkSurface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.darkBorder),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withValues(alpha: 0.08),
              blurRadius: 40,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animated globe icon
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 800),
              curve: Curves.elasticOut,
              builder: (context, value, child) {
                return Transform.scale(scale: value, child: child);
              },
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primary.withValues(alpha: 0.2),
                      AppTheme.secondary.withValues(alpha: 0.1),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.public_off_rounded, size: 56, color: AppTheme.primary),
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'In-App Browsing Unavailable',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'In-App Browsing is disabled on the Web version due to browser '
              'security restrictions (X-Frame-Options). E-commerce sites like '
              'Shein and Trendyol block embedding in iframes.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.6),
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.secondary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.secondary.withValues(alpha: 0.2)),
              ),
              child: Column(
                children: [
                  const Row(
                    children: [
                      Icon(Icons.lightbulb_outline, color: AppTheme.secondary, size: 20),
                      SizedBox(width: 10),
                      Text('How to use this feature', style: TextStyle(color: AppTheme.secondary, fontWeight: FontWeight.w600, fontSize: 14)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '• Compile as a Native Desktop app (Windows/macOS)\n'
                    '• Or compile as a Mobile app (Android/iOS)',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13, height: 1.6),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── NATIVE BROWSER ───────────────────────────────────
  Widget _buildNativeBrowser() {
    return Column(
      children: [
        // Address Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.darkSurface,
            border: Border(bottom: BorderSide(color: AppTheme.darkBorder.withValues(alpha: 0.5))),
          ),
          child: Row(
            children: [
              // Navigation buttons
              _NavButton(icon: Icons.arrow_back_ios_new_rounded, onTap: () => goBack()),
              const SizedBox(width: 4),
              _NavButton(icon: Icons.arrow_forward_ios_rounded, onTap: () => goForward()),
              const SizedBox(width: 4),
              _NavButton(icon: Icons.refresh_rounded, onTap: () => reload()),
              const SizedBox(width: 12),

              // URL Field
              Expanded(
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.darkCard,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.darkBorder),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      const Icon(Icons.lock_outline, size: 14, color: AppTheme.success),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _urlController,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: const InputDecoration(
                            hintText: 'Enter URL...',
                            hintStyle: TextStyle(color: Colors.white30),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onSubmitted: (url) => navigateTo(url),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Quick navigation chips
              _QuickChip(label: 'Shein', onTap: () => navigateTo('https://www.shein.com/cart')),
              const SizedBox(width: 6),
              _QuickChip(label: 'Trendyol', onTap: () => navigateTo('https://www.trendyol.com/sepet')),
            ],
          ),
        ),

        // WebView body
        Expanded(
          child: Stack(
            children: [
              buildWebView(
                initialUrl: 'https://www.shein.com',
                onUrlChanged: (url) {
                  if (mounted) {
                    _urlController.text = url;
                  }
                },
              ),

              // Loading overlay
              if (_isExtracting)
                Container(
                  color: Colors.black54,
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: AppTheme.primary),
                        SizedBox(height: 16),
                        Text('Extracting cart items...', style: TextStyle(color: Colors.white, fontSize: 16)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Bottom Action Bar
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.darkSurface,
            border: Border(top: BorderSide(color: AppTheme.darkBorder.withValues(alpha: 0.5))),
          ),
          child: Row(
            children: [
              // Current page info
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.shopping_bag_rounded, color: AppTheme.primary, size: 18),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Navigate to your cart, then extract items',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Extract button
              SizedBox(
                height: 44,
                child: ElevatedButton.icon(
                  onPressed: _isExtracting ? null : _extractCart,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.inventory_2_rounded, size: 20),
                  label: const Text('Extract Cart to System', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── EXTRACTION LOGIC ─────────────────────────────────
  Future<void> _extractCart() async {
    setState(() => _isExtracting = true);

    try {
      // Inject the extraction JavaScript into the WebView
      final resultJson = await runExtractionJs(cartExtractionJs);
      if (resultJson == null || resultJson.isEmpty) {
        throw Exception('No data returned from page');
      }

      // Parse the JSON result (WebView may wrap in quotes)
      String cleanJson = resultJson;
      if (cleanJson.startsWith('"') && cleanJson.endsWith('"')) {
        cleanJson = jsonDecode(cleanJson) as String;
      }

      final result = jsonDecode(cleanJson) as Map<String, dynamic>;

      if (result['success'] != true) {
        throw Exception(result['error'] ?? 'Extraction failed');
      }

      final items = List<Map<String, dynamic>>.from(
        (result['items'] as List).map((e) => Map<String, dynamic>.from(e)),
      );

      if (items.isEmpty) {
        throw Exception('No items found in cart');
      }

      if (!mounted) return;

      // Show confirmation dialog
      _showConfirmationDialog(items, result['platform'] as String? ?? 'unknown');

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Extraction failed: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExtracting = false);
    }
  }

  // ─── CONFIRMATION DIALOG ──────────────────────────────
  void _showConfirmationDialog(List<Map<String, dynamic>> items, String platform) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ConfirmOrderDialog(
        items: items,
        platform: platform,
        onConfirm: (customerName, customerPhone) async {
          await _createOrder(items, platform, customerName, customerPhone);
        },
      ),
    );
  }

  Future<void> _createOrder(
    List<Map<String, dynamic>> items,
    String platform,
    String customerName,
    String customerPhone,
  ) async {
    // No try/catch: errors propagate to _ConfirmOrderDialog._submit() which
    // sets _error state and keeps the dialog open so the user can retry.
    final customerId = await _findOrCreateCustomer(customerName, customerPhone);

    final orderId = const Uuid().v4();
    final orderItems = items.map((item) => {
      'id': const Uuid().v4(),
      'product_name': item['product_name'] ?? 'Unknown',
      'product_image_url': item['image_url'] ?? '',
      'quantity': item['quantity'] ?? 1,
      'unit_price_foreign': (item['price'] as num?)?.toDouble() ?? 0,
      'unit_price_local': 0,
      'color': item['color'] ?? '',
      'size': item['size'] ?? '',
      'sku': item['sku'] ?? '',
      'notes': 'Extracted from $platform via In-App Browser',
    }).toList();

    await ref.read(ordersProvider.notifier).createOrder({
      'id': orderId,
      'customer_id': customerId,
      'platform': platform,
      'currency': 'USD',
      'items': orderItems,
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Order created! ${items.length} items pushed.'),
          backgroundColor: AppTheme.success,
        ),
      );
    }
  }

  Future<String> _findOrCreateCustomer(String name, String phone) async {
    // Phone-first identity: if a phone is provided, use exact phone lookup
    // (name lookup is non-unique and bypasses the phone-first identity pattern)
    if (phone.isNotEmpty) {
      final existing = await ref.read(customersProvider.notifier).lookupByPhone(phone);
      if (existing != null) return existing['id'] as String;
    }

    // Create via silent upsert and return the ID the backend actually assigned,
    // not a locally-generated UUID (which would be wrong on a phone collision).
    final result = await ref.read(customersProvider.notifier).createCustomer({
      'id': const Uuid().v4(),
      'full_name': name,
      'phone': phone.isNotEmpty ? phone : null,
    });
    return result['id'] as String;
  }
}

// ─── Confirmation Dialog ─────────────────────────────────

class _ConfirmOrderDialog extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final String platform;
  final Future<void> Function(String name, String phone) onConfirm;

  const _ConfirmOrderDialog({
    required this.items,
    required this.platform,
    required this.onConfirm,
  });

  @override
  State<_ConfirmOrderDialog> createState() => _ConfirmOrderDialogState();
}

class _ConfirmOrderDialogState extends State<_ConfirmOrderDialog> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.check_circle_outline, color: AppTheme.success, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Confirm Order',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
                        Text('${widget.items.length} items from ${widget.platform}',
                          style: const TextStyle(color: Colors.white54, fontSize: 13)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white38),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Error
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_error!, style: const TextStyle(color: AppTheme.error, fontSize: 13)),
                ),

              // Items preview (scrollable)
              Flexible(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.darkCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.darkBorder),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(12),
                    itemCount: widget.items.length,
                    separatorBuilder: (_, __) => const Divider(height: 16, color: AppTheme.darkBorder),
                    itemBuilder: (context, index) {
                      final item = widget.items[index];
                      return Row(
                        children: [
                          // Image
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: 48, height: 48,
                              color: AppTheme.darkSurface,
                              child: (item['image_url'] ?? '').toString().isNotEmpty
                                ? Image.network(item['image_url'], fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(Icons.image, color: Colors.white24))
                                : const Icon(Icons.image, color: Colors.white24),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['product_name'] ?? 'Unknown',
                                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    if ((item['size'] ?? '').toString().isNotEmpty)
                                      _Tag(label: item['size']),
                                    if ((item['color'] ?? '').toString().isNotEmpty)
                                      _Tag(label: item['color']),
                                    if ((item['sku'] ?? '').toString().isNotEmpty)
                                      _Tag(label: 'SKU: ${item['sku']}', color: AppTheme.primary),
                                    if ((item['sku'] ?? '').toString().isEmpty)
                                      _Tag(label: '⚠ No SKU', color: AppTheme.warning),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          // Price
                          Text(
                            '\$${((item['price'] as num?) ?? 0).toStringAsFixed(2)}',
                            style: const TextStyle(color: AppTheme.secondary, fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Customer fields
              TextField(
                controller: _nameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Customer Name *',
                  prefixIcon: const Icon(Icons.person_outline),
                  filled: true, fillColor: AppTheme.darkCard,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _phoneCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Phone (optional)',
                  prefixIcon: const Icon(Icons.phone_outlined),
                  filled: true, fillColor: AppTheme.darkCard,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 16),

              // Confirm button
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _sending ? null : _submit,
                  icon: _sending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded, size: 20),
                  label: Text(_sending ? 'Creating Order...' : 'Create Order & Push'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.success,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Customer name is required');
      return;
    }
    setState(() { _sending = true; _error = null; });
    try {
      await widget.onConfirm(_nameCtrl.text.trim(), _phoneCtrl.text.trim());
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}

// ─── Helper Widgets ──────────────────────────────────────

class _NavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _NavButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppTheme.darkCard,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: Colors.white70),
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _QuickChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
        ),
        child: Text(label, style: const TextStyle(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color color;
  const _Tag({required this.label, this.color = AppTheme.secondary});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w500)),
    );
  }
}
