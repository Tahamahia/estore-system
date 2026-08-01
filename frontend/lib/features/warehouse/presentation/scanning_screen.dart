import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:estore_app/app/theme.dart';
import 'package:estore_app/core/api_client.dart';
import 'package:estore_app/core/providers.dart';
import 'package:estore_app/core/utils/dialog_utils.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';

class ScanningScreen extends ConsumerStatefulWidget {
  const ScanningScreen({super.key});
  @override
  ConsumerState<ScanningScreen> createState() => _ScanningScreenState();
}

class _ScanningScreenState extends ConsumerState<ScanningScreen> with TickerProviderStateMixin {
  final FocusNode _focusNode = FocusNode();
  final _manualController = TextEditingController();
  String _buffer = '';
  DateTime _lastKeyTime = DateTime.now();
  String? _lastScannedCode;
  final List<_ScanResult> _scanHistory = [];

  // Flash overlay state
  bool _showFlash = false;
  Color _flashColor = AppTheme.success;
  String _flashCustomer = '';
  String _flashProduct = '';
  Map<String, dynamic>? _flashOrderProgress;
  late AnimationController _flashAnimCtrl;
  late Animation<double> _flashAnim;

  @override
  void initState() {
    super.initState();
    _flashAnimCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 3000));
    _flashAnim = CurvedAnimation(parent: _flashAnimCtrl, curve: Curves.easeOut);
    _flashAnimCtrl.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) setState(() => _showFlash = false);
    });
    Future.microtask(_loadTodayHistory);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _manualController.dispose();
    _flashAnimCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTodayHistory() async {
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.get('/warehouse/scan-history');
      final data = res.data as Map<String, dynamic>;
      final items = List<Map<String, dynamic>>.from(data['data'] ?? []);
      if (mounted && items.isNotEmpty) {
        setState(() {
          for (final item in items) {
            final rawId = item['id'] as String? ?? '';
            _scanHistory.add(_ScanResult(
              barcode: item['sku'] as String? ?? (rawId.length > 8 ? rawId.substring(0, 8) : rawId),
              timestamp: DateTime.tryParse(item['sorted_at'] as String? ?? '') ?? DateTime.now(),
              status: _ScanStatus.found,
              customerName: item['customer_name'] as String?,
              productName: item['product_name'] as String?,
            ));
          }
        });
      }
    } catch (_) {
      // silent fail — start with empty list
    }
  }

  void _playAudioCue(bool success, {bool bagComplete = false}) {
    SystemSound.play(SystemSoundType.click);
    if (success) {
      if (bagComplete) {
        HapticFeedback.heavyImpact();
        Future.delayed(const Duration(milliseconds: 120), () => HapticFeedback.heavyImpact());
      } else {
        HapticFeedback.mediumImpact();
      }
    } else {
      HapticFeedback.heavyImpact();
    }
  }

  void _showMassiveFlash({required bool success, String? customer, String? product, Map<String, dynamic>? orderProgress}) {
    final bagComplete = success && (orderProgress?['complete'] == true);
    setState(() {
      _showFlash = true;
      _flashColor = !success ? AppTheme.error : bagComplete ? Colors.amber : AppTheme.success;
      _flashCustomer = customer ?? '';
      _flashProduct = product ?? '';
      _flashOrderProgress = orderProgress;
    });
    _flashAnimCtrl.reset();
    _flashAnimCtrl.forward();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final now = DateTime.now();
    if (now.difference(_lastKeyTime).inMilliseconds > 100) _buffer = '';
    _lastKeyTime = now;
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_buffer.isNotEmpty) { _processBarcode(_buffer); _buffer = ''; }
    } else {
      final char = event.character;
      if (char != null && char.isNotEmpty) _buffer += char;
    }
  }

  Future<void> _processBarcode(String barcode) async {
    setState(() {
      _lastScannedCode = barcode;
      _scanHistory.insert(0, _ScanResult(barcode: barcode, timestamp: DateTime.now(), status: _ScanStatus.processing));
    });
    try {
      await ref.read(scanResultProvider.notifier).scanBarcode(barcode);
      final scanState = ref.read(scanResultProvider);
      if (mounted && scanState.hasError) {
        setState(() => _scanHistory[0] = _scanHistory[0].copyWith(
          status: _ScanStatus.error, errorMsg: scanState.error?.toString() ?? 'خطأ في الشبكة'));
        _playAudioCue(false);
        _showMassiveFlash(success: false);
        return;
      }
      final scanResult = scanState.valueOrNull;
      if (mounted && scanResult != null) {
        final found = scanResult['found'] == true;
        final ambiguous = scanResult['ambiguous'] == true;
        final hasError = scanResult['error'] != null;
        final itemMap = scanResult['item'] as Map<String, dynamic>?;
        final candidatesList = scanResult['candidates'] as List<dynamic>?;
        final orderProgress = scanResult['order_progress'] as Map<String, dynamic>?;
        String? custName;
        String? prodName;
        if (found && !ambiguous && !hasError && itemMap != null) {
          custName = itemMap['customer_name'] as String?;
          prodName = itemMap['product_name'] as String?;
        }
        final isSuccess = found && !ambiguous && !hasError;
        setState(() {
          _scanHistory[0] = _scanHistory[0].copyWith(
            status: !found ? _ScanStatus.notFound
                : hasError ? _ScanStatus.error
                : ambiguous ? _ScanStatus.ambiguous
                : _ScanStatus.found,
            customerName: custName, productName: prodName,
            errorMsg: hasError ? (scanResult['message'] as String?) : null,
            candidates: ambiguous && !hasError && candidatesList != null ? candidatesList.cast<Map<String, dynamic>>() : null,
            orderProgress: isSuccess ? orderProgress : null,
          );
        });
        _playAudioCue(isSuccess, bagComplete: orderProgress?['complete'] == true);
        _showMassiveFlash(success: isSuccess, customer: custName, product: prodName, orderProgress: orderProgress);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _scanHistory[0] = _scanHistory[0].copyWith(status: _ScanStatus.error, errorMsg: e.toString()));
        _playAudioCue(false);
        _showMassiveFlash(success: false);
      }
    }
  }

  Future<void> _logOrphan(String barcode) async {
    try {
      await ref.read(scanResultProvider.notifier).logOrphan({
        'id': const Uuid().v4(), 'barcode': barcode, 'description': 'قطعة مجهولة — باركود غير معروف',
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تسجيل القطعة المجهولة'), backgroundColor: AppTheme.warning));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل: $e'), backgroundColor: AppTheme.error));
    }
  }

  void _openVisualMatch() {
    showDialog(context: context, builder: (_) => _VisualMatchDialog(
      onItemSelected: (itemId, customerName) async {
        try {
          await ref.read(scanResultProvider.notifier).scanBarcode(itemId);
          if (mounted) {
            final scanState = ref.read(scanResultProvider);
            final scanResult = scanState.valueOrNull;
            final orderProgress = scanResult?['order_progress'] as Map<String, dynamic>?;
            _playAudioCue(true, bagComplete: orderProgress?['complete'] == true);
            _showMassiveFlash(success: true, customer: customerName, orderProgress: orderProgress);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('✅ تم الفرز إلى $customerName'), backgroundColor: AppTheme.success,
            ));
          }
        } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل: $e'), backgroundColor: AppTheme.error));
        }
      },
    ));
  }

  void _selectAmbiguousCandidate(Map<String, dynamic> candidate) {
    final customerName = candidate['customer_name'] as String? ?? 'غير معروف';
    final productName = candidate['product_name'] as String? ?? 'غير معروف';
    final itemId = candidate['id'] as String? ?? '';

    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: AppTheme.darkCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('هل هذا هو العنصر الصحيح؟', style: TextStyle(color: Colors.white, fontSize: 18)),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(productName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
        const SizedBox(height: 8),
        Text('العميل: $customerName', style: const TextStyle(color: Colors.white70, fontSize: 14)),
        if (candidate['size'] != null || candidate['color'] != null) ...[
          const SizedBox(height: 4),
          Text('${candidate['size'] ?? ''} ${candidate['color'] ?? ''}'.trim(), style: const TextStyle(color: Colors.white54, fontSize: 13)),
        ],
      ]),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء', style: TextStyle(fontSize: 15)),
        ),
        ElevatedButton.icon(
          onPressed: () async {
            Navigator.pop(context);
            try {
              await ref.read(scanResultProvider.notifier).scanBarcode(itemId);
              if (mounted) {
                final scanState = ref.read(scanResultProvider);
                final scanResult = scanState.valueOrNull;
                final orderProgress = scanResult?['order_progress'] as Map<String, dynamic>?;
                _playAudioCue(true, bagComplete: orderProgress?['complete'] == true);
                _showMassiveFlash(success: true, customer: customerName, orderProgress: orderProgress);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('✅ تم الفرز إلى $customerName'), backgroundColor: AppTheme.success,
                ));
              }
            } catch (e) {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل: $e'), backgroundColor: AppTheme.error));
            }
          },
          icon: const Icon(Icons.check, size: 20),
          label: const Text('نعم، فرز', style: TextStyle(fontSize: 15)),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
        ),
      ],
    ));
  }

  int get _todaySortedCount => _scanHistory.where((s) => s.status == _ScanStatus.found).length;

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode, autofocus: true, onKeyEvent: _handleKeyEvent,
      child: GestureDetector(
        onTap: () => _focusNode.requestFocus(),
        child: Stack(children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _buildScannerBanner(),
              const SizedBox(height: 24),
              Expanded(
                child: LayoutBuilder(builder: (context, constraints) {
                  if (constraints.maxWidth > 800) {
                    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(flex: 2, child: _buildScanHistory()),
                      const SizedBox(width: 24),
                      Expanded(child: _buildManualEntry()),
                    ]);
                  }
                  return Column(children: [
                    _buildManualEntry(),
                    const SizedBox(height: 24),
                    Expanded(child: _buildScanHistory()),
                  ]);
                }),
              ),
            ]),
          ),
          // Massive flash overlay
          if (_showFlash)
            AnimatedBuilder(
              animation: _flashAnim,
              builder: (ctx, _) {
                final opacity = (1.0 - _flashAnim.value).clamp(0.0, 1.0);
                final progress = _flashOrderProgress;
                final bagComplete = _flashColor == Colors.amber;
                final isSuccess = _flashColor != AppTheme.error;
                return Positioned.fill(
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: opacity,
                      child: Container(
                        color: _flashColor.withValues(alpha: 0.92),
                        child: Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(
                              isSuccess ? Icons.check_circle_rounded : Icons.cancel_rounded,
                              size: 100, color: Colors.white,
                            ),
                            const SizedBox(height: 20),
                            if (_flashCustomer.isNotEmpty) ...[
                              Text(_flashCustomer, style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 16),
                            ],
                            if (isSuccess && progress != null) ...[
                              if (bagComplete)
                                const Text(
                                  '✅ الكيس اكتمل — جاهز للتوصيل',
                                  style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900),
                                  textAlign: TextAlign.center,
                                )
                              else
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    'منتج ${progress['sorted']} من ${progress['total']} ✓',
                                    style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700),
                                  ),
                                ),
                            ],
                            if (!isSuccess) ...[
                              const SizedBox(height: 16),
                              const Text('❌ غير موجود', style: TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w900)),
                            ],
                            if (_flashProduct.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              Text(_flashProduct, style: const TextStyle(color: Colors.white70, fontSize: 20), textAlign: TextAlign.center),
                            ],
                          ]),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        ]),
      ),
    );
  }

  Widget _buildScannerBanner() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [AppTheme.primary.withValues(alpha: 0.2), AppTheme.secondary.withValues(alpha: 0.1)]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppTheme.success.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.qr_code_scanner, color: AppTheme.success, size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppTheme.success, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            const Text('السكانر جاهز', style: TextStyle(color: AppTheme.success, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 4),
          const Text('امسح الباركود أو استخدم المطابقة البصرية للملصقات التالفة', style: TextStyle(color: Colors.white54, fontSize: 13)),
        ])),
        // Two info chips: last scan + today count
        Row(mainAxisSize: MainAxisSize.min, children: [
          if (_lastScannedCode != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: AppTheme.darkCard, borderRadius: BorderRadius.circular(10)),
              child: Column(children: [
                const Text('آخر مسح', style: TextStyle(color: Colors.white38, fontSize: 11)),
                const SizedBox(height: 2),
                Text(_lastScannedCode!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
              ]),
            ),
            const SizedBox(width: 8),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: AppTheme.success.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.success.withValues(alpha: 0.3))),
            child: Column(children: [
              const Text('مفروز اليوم', style: TextStyle(color: Colors.white38, fontSize: 11)),
              const SizedBox(height: 2),
              Text('$_todaySortedCount', style: const TextStyle(color: AppTheme.success, fontWeight: FontWeight.w700, fontSize: 18)),
            ]),
          ),
        ]),
      ]),
    );
  }

  Widget _buildScanHistory() {
    return Container(
      decoration: BoxDecoration(color: AppTheme.darkSurface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.darkBorder)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            const Text('سجل الفرز', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
            const Spacer(),
            Text('${_scanHistory.length} عملية', style: const TextStyle(color: Colors.white38, fontSize: 13)),
          ]),
        ),
        const Divider(height: 1, color: AppTheme.darkBorder),
        Expanded(
          child: _scanHistory.isEmpty
            ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.qr_code, size: 48, color: Colors.white24),
                SizedBox(height: 12),
                Text('لا توجد عمليات فرز بعد', style: TextStyle(color: Colors.white38)),
              ]))
            : ListView.separated(
                padding: const EdgeInsets.all(12), itemCount: _scanHistory.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) => _ScanTile(
                  scan: _scanHistory[index],
                  onLogOrphan: () => _logOrphan(_scanHistory[index].barcode),
                  onSelectCandidate: _selectAmbiguousCandidate,
                ),
              ),
        ),
      ]),
    );
  }

  Widget _buildManualEntry() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppTheme.darkSurface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.darkBorder)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        const Text('إدخال يدوي', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
        const SizedBox(height: 16),
        TextField(
          controller: _manualController,
          decoration: const InputDecoration(hintText: 'أدخل الباركود يدوياً...', hintStyle: TextStyle(color: Colors.white38), prefixIcon: Icon(Icons.keyboard, color: Colors.white38)),
          style: const TextStyle(color: Colors.white),
          onSubmitted: (v) { if (v.isNotEmpty) { _processBarcode(v); _manualController.clear(); } _focusNode.requestFocus(); },
        ),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: ElevatedButton.icon(
          onPressed: () { final c = _lastScannedCode; if (c != null) _logOrphan(c); },
          icon: const Icon(Icons.inventory_2_outlined, size: 20), label: const Text('تسجيل كقطعة مجهولة'),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.warning),
        )),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, child: ElevatedButton.icon(
          onPressed: _openVisualMatch,
          icon: const Icon(Icons.visibility_rounded, size: 20), label: const Text('👁️ مطابقة بصرية (ملصق تالف)'),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent, foregroundColor: Colors.white),
        )),
      ]),
    );
  }
}

// ─── Visual Match Dialog ─────────────────────────────────────
class _VisualMatchDialog extends ConsumerStatefulWidget {
  final Future<void> Function(String itemId, String customerName) onItemSelected;
  const _VisualMatchDialog({required this.onItemSelected});
  @override
  ConsumerState<_VisualMatchDialog> createState() => _VisualMatchDialogState();
}

class _VisualMatchDialogState extends ConsumerState<_VisualMatchDialog> {
  List<Map<String, dynamic>>? _items;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    try {
      final items = await ref.read(ordersProvider.notifier).fetchUnsortedItems();
      if (mounted) setState(() { _items = items; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 700, maxHeight: dialogMaxHeight(context, cap: 600)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.visibility_rounded, color: AppTheme.accent),
              const SizedBox(width: 10),
              const Text('مطابقة بصرية — اضغط على المنتج الذي تراه', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(icon: const Icon(Icons.close, color: Colors.white38), onPressed: () => Navigator.pop(context)),
            ]),
            const SizedBox(height: 4),
            const Text('يعرض المنتجات المشتراة والمشحونة المتوقع وصولها', style: TextStyle(color: Colors.white38, fontSize: 12)),
            const SizedBox(height: 16),
            Expanded(
              child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                  ? Center(child: Text(_error!, style: const TextStyle(color: AppTheme.error)))
                  : (_items == null || _items!.isEmpty)
                    ? const Center(child: Text('لا توجد منتجات غير مفروزة', style: TextStyle(color: Colors.white38)))
                    : GridView.builder(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 0.75, crossAxisSpacing: 10, mainAxisSpacing: 10),
                        itemCount: _items!.length,
                        itemBuilder: (ctx, i) {
                          final item = _items![i];
                          return _VisualMatchCard(
                            item: item,
                            onTap: () => _confirmMatch(item),
                          );
                        },
                      ),
            ),
          ]),
        ),
      ),
    );
  }

  void _confirmMatch(Map<String, dynamic> item) {
    final customerName = item['customer_name'] as String? ?? 'غير معروف';
    final productName = item['product_name'] as String? ?? 'غير معروف';
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: AppTheme.darkCard,
      title: const Text('تأكيد المطابقة', style: TextStyle(color: Colors.white)),
      content: Text('فرز "$productName" للزبون $customerName؟', style: const TextStyle(color: Colors.white70)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        ElevatedButton(
          onPressed: () async {
            Navigator.pop(context); // close confirm
            Navigator.pop(context); // close grid
            await widget.onItemSelected(item['id'] as String, customerName);
          },
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
          child: const Text('فرز'),
        ),
      ],
    ));
  }
}

class _VisualMatchCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  const _VisualMatchCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final imgUrl = (item['product_image_url'] ?? item['product_thumb_url'] ?? '').toString();
    return InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(color: AppTheme.darkCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.darkBorder)),
        child: Column(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: imgUrl.isNotEmpty
                ? Image.network(imgUrl, fit: BoxFit.cover, width: double.infinity, errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.image, color: Colors.white24, size: 40)))
                : const Center(child: Icon(Icons.image, color: Colors.white24, size: 40)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item['product_name'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text('${item['customer_name'] ?? ''} · ${item['size'] ?? ''} ${item['color'] ?? ''}',
                style: const TextStyle(color: Colors.white54, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ─── Data Models ───────────────────────────────────────────
enum _ScanStatus { processing, found, notFound, ambiguous, error }

class _ScanResult {
  final String barcode;
  final DateTime timestamp;
  final _ScanStatus status;
  final String? customerName;
  final String? productName;
  final String? errorMsg;
  final List<Map<String, dynamic>>? candidates;
  final Map<String, dynamic>? orderProgress;

  _ScanResult({
    required this.barcode,
    required this.timestamp,
    required this.status,
    this.customerName,
    this.productName,
    this.errorMsg,
    this.candidates,
    this.orderProgress,
  });

  _ScanResult copyWith({
    _ScanStatus? status,
    String? customerName,
    String? productName,
    String? errorMsg,
    List<Map<String, dynamic>>? candidates,
    Map<String, dynamic>? orderProgress,
  }) {
    return _ScanResult(
      barcode: barcode,
      timestamp: timestamp,
      status: status ?? this.status,
      customerName: customerName ?? this.customerName,
      productName: productName ?? this.productName,
      errorMsg: errorMsg ?? this.errorMsg,
      candidates: candidates ?? this.candidates,
      orderProgress: orderProgress ?? this.orderProgress,
    );
  }
}

class _ScanTile extends StatelessWidget {
  final _ScanResult scan;
  final VoidCallback onLogOrphan;
  final void Function(Map<String, dynamic> candidate) onSelectCandidate;
  const _ScanTile({required this.scan, required this.onLogOrphan, required this.onSelectCandidate});

  @override
  Widget build(BuildContext context) {
    Color statusColor; IconData statusIcon; String statusText;
    switch (scan.status) {
      case _ScanStatus.processing: statusColor = AppTheme.warning; statusIcon = Icons.hourglass_top; statusText = 'جاري البحث...';
      case _ScanStatus.found: statusColor = AppTheme.success; statusIcon = Icons.check_circle; statusText = 'تم الفرز ✓';
      case _ScanStatus.notFound: statusColor = AppTheme.error; statusIcon = Icons.error; statusText = 'غير موجود';
      case _ScanStatus.ambiguous: statusColor = AppTheme.accent; statusIcon = Icons.help; statusText = 'تعدد النتائج';
      case _ScanStatus.error: statusColor = AppTheme.error; statusIcon = Icons.wifi_off; statusText = 'خطأ';
    }
    final progress = scan.orderProgress;
    final bagComplete = progress?['complete'] == true;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppTheme.darkCard.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(12), border: Border.all(color: statusColor.withValues(alpha: 0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(statusIcon, color: statusColor, size: 22), const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(scan.barcode, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            if (scan.productName != null) Text('${scan.productName} → ${scan.customerName}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
            if (scan.errorMsg != null) Text(scan.errorMsg!, style: const TextStyle(color: AppTheme.error, fontSize: 12)),
          ])),
          Text(statusText, style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
        // Progress line
        if (scan.status == _ScanStatus.found && progress != null) ...[
          const SizedBox(height: 6),
          if (bagComplete)
            const Text('✅ الكيس اكتمل', style: TextStyle(color: AppTheme.success, fontSize: 11, fontWeight: FontWeight.w700))
          else ...[
            Text('${progress['sorted']} من ${progress['total']} منتج في الطلبية', style: const TextStyle(color: Colors.white38, fontSize: 11)),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (progress['total'] as num) > 0
                    ? (progress['sorted'] as num) / (progress['total'] as num)
                    : 0.0,
                backgroundColor: Colors.white12,
                valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.success),
                minHeight: 4,
              ),
            ),
          ],
        ],
        if (scan.status == _ScanStatus.notFound) ...[
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, height: 32, child: OutlinedButton.icon(
            onPressed: onLogOrphan, icon: const Icon(Icons.add_box_outlined, size: 16), label: const Text('تسجيل كمجهول', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(foregroundColor: AppTheme.warning, side: BorderSide(color: AppTheme.warning.withValues(alpha: 0.5))),
          )),
        ],
        if (scan.status == _ScanStatus.ambiguous && scan.candidates != null) ...[
          const SizedBox(height: 8),
          const Text('اختر العنصر الصحيح:', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          ...scan.candidates!.map((c) => Padding(
            padding: const EdgeInsets.only(top: 4),
            child: InkWell(
              onTap: () => onSelectCandidate(c),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.person_outline, size: 18, color: AppTheme.accent),
                  const SizedBox(width: 8),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(c['product_name'] ?? 'غير معروف', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                    Text(c['customer_name'] ?? '', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  ])),
                  const Icon(Icons.touch_app, color: AppTheme.accent, size: 20),
                ]),
              ),
            ),
          )),
        ],
      ]),
    );
  }
}
