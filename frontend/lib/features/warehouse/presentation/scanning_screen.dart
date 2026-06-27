import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:estore_app/app/theme.dart';
import 'package:estore_app/core/providers.dart';
import 'package:uuid/uuid.dart';

/// Warehouse Scanning Screen — HardwareKeyboard barcode capture
/// Fires API lookup immediately on Enter keystroke without UI freeze.
class ScanningScreen extends ConsumerStatefulWidget {
  const ScanningScreen({super.key});

  @override
  ConsumerState<ScanningScreen> createState() => _ScanningScreenState();
}

class _ScanningScreenState extends ConsumerState<ScanningScreen> {
  final FocusNode _focusNode = FocusNode();
  final _manualController = TextEditingController();
  String _buffer = '';
  DateTime _lastKeyTime = DateTime.now();
  String? _lastScannedCode;
  final List<_ScanResult> _scanHistory = [];

  @override
  void dispose() {
    _focusNode.dispose();
    _manualController.dispose();
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    final now = DateTime.now();
    // Hardware scanners send keystrokes < 50ms apart
    // Manual typing is > 100ms. Reset buffer for manual.
    if (now.difference(_lastKeyTime).inMilliseconds > 100) {
      _buffer = '';
    }
    _lastKeyTime = now;

    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_buffer.isNotEmpty) {
        _processBarcode(_buffer);
        _buffer = '';
      }
    } else {
      final char = event.character;
      if (char != null && char.isNotEmpty) {
        _buffer += char;
      }
    }
  }

  Future<void> _processBarcode(String barcode) async {
    setState(() {
      _lastScannedCode = barcode;
      _scanHistory.insert(0, _ScanResult(
        barcode: barcode,
        timestamp: DateTime.now(),
        status: _ScanStatus.processing,
      ));
    });

    // Fire API call immediately — non-blocking
    try {
      await ref.read(scanResultProvider.notifier).scanBarcode(barcode);
      final scanResult = ref.read(scanResultProvider).valueOrNull;

      if (mounted && scanResult != null) {
        setState(() {
          final found = scanResult['found'] == true;
          final ambiguous = scanResult['ambiguous'] == true;

          final itemMap = scanResult['item'] as Map<String, dynamic>?;
          final candidatesList = scanResult['candidates'] as List<dynamic>?;

          String? custName;
          String? prodName;
          if (found && !ambiguous && itemMap != null) {
            custName = itemMap['customer_name'] as String?;
            prodName = itemMap['product_name'] as String?;
          }

          _scanHistory[0] = _scanHistory[0].copyWith(
            status: !found
                ? _ScanStatus.notFound
                : ambiguous
                    ? _ScanStatus.ambiguous
                    : _ScanStatus.found,
            customerName: custName,
            productName: prodName,
            candidates: ambiguous && candidatesList != null
                ? candidatesList.cast<Map<String, dynamic>>()
                : null,
          );
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _scanHistory[0] = _scanHistory[0].copyWith(
            status: _ScanStatus.error,
            errorMsg: e.toString(),
          );
        });
      }
    }
  }

  Future<void> _logOrphan(String barcode) async {
    try {
      await ref.read(scanResultProvider.notifier).logOrphan({
        'id': const Uuid().v4(),
        'barcode': barcode,
        'description': 'Orphaned package — unrecognized barcode',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Orphaned package logged to Lost & Found'),
            backgroundColor: AppTheme.warning,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to log orphan: $e'), backgroundColor: AppTheme.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: GestureDetector(
        onTap: () => _focusNode.requestFocus(),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Scanner Status Banner
              _buildScannerBanner(),
              const SizedBox(height: 24),

              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth > 800) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 2, child: _buildScanHistory()),
                          const SizedBox(width: 24),
                          Expanded(child: _buildManualEntry()),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        _buildManualEntry(),
                        const SizedBox(height: 24),
                        Expanded(child: _buildScanHistory()),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScannerBanner() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primary.withValues(alpha: 0.2), AppTheme.secondary.withValues(alpha: 0.1)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.success.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.qr_code_scanner, color: AppTheme.success, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppTheme.success, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  const Text('Scanner Ready', style: TextStyle(color: AppTheme.success, fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: 4),
                const Text('Scan any barcode — input captured via keyboard listener',
                  style: TextStyle(color: Colors.white54, fontSize: 13)),
              ],
            ),
          ),
          if (_lastScannedCode != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: AppTheme.darkCard, borderRadius: BorderRadius.circular(10)),
              child: Column(
                children: [
                  const Text('Last Scan', style: TextStyle(color: Colors.white38, fontSize: 11)),
                  const SizedBox(height: 2),
                  Text(_lastScannedCode!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildScanHistory() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.darkSurface, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              const Text('Scan History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
              const Spacer(),
              Text('${_scanHistory.length} scans', style: const TextStyle(color: Colors.white38, fontSize: 13)),
            ]),
          ),
          const Divider(height: 1, color: AppTheme.darkBorder),
          Expanded(
            child: _scanHistory.isEmpty
                ? const Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.qr_code, size: 48, color: Colors.white24),
                      SizedBox(height: 12),
                      Text('No scans yet', style: TextStyle(color: Colors.white38)),
                      Text('Scan a barcode to begin', style: TextStyle(color: Colors.white24, fontSize: 13)),
                    ]),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _scanHistory.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => _ScanTile(
                      scan: _scanHistory[index],
                      onLogOrphan: () => _logOrphan(_scanHistory[index].barcode),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildManualEntry() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Manual Entry', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
          const SizedBox(height: 16),
          TextField(
            controller: _manualController,
            decoration: const InputDecoration(
              hintText: 'Enter barcode manually...',
              hintStyle: TextStyle(color: Colors.white38),
              prefixIcon: Icon(Icons.keyboard, color: Colors.white38),
            ),
            style: const TextStyle(color: Colors.white),
            onSubmitted: (value) {
              if (value.isNotEmpty) {
                _processBarcode(value);
                _manualController.clear();
              }
              _focusNode.requestFocus(); // Return focus to scanner listener
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                final code = _lastScannedCode;
                if (code != null) _logOrphan(code);
              },
              icon: const Icon(Icons.inventory_2_outlined, size: 20),
              label: const Text('Log Last as Orphan'),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.warning),
            ),
          ),
        ],
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

  _ScanResult({
    required this.barcode, required this.timestamp, required this.status,
    this.customerName, this.productName, this.errorMsg, this.candidates,
  });

  _ScanResult copyWith({
    _ScanStatus? status, String? customerName, String? productName,
    String? errorMsg, List<Map<String, dynamic>>? candidates,
  }) {
    return _ScanResult(
      barcode: barcode, timestamp: timestamp,
      status: status ?? this.status,
      customerName: customerName ?? this.customerName,
      productName: productName ?? this.productName,
      errorMsg: errorMsg ?? this.errorMsg,
      candidates: candidates ?? this.candidates,
    );
  }
}

class _ScanTile extends StatelessWidget {
  final _ScanResult scan;
  final VoidCallback onLogOrphan;
  const _ScanTile({required this.scan, required this.onLogOrphan});

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (scan.status) {
      case _ScanStatus.processing:
        statusColor = AppTheme.warning;
        statusIcon = Icons.hourglass_top;
        statusText = 'Processing...';
      case _ScanStatus.found:
        statusColor = AppTheme.success;
        statusIcon = Icons.check_circle;
        statusText = 'Sorted ✓';
      case _ScanStatus.notFound:
        statusColor = AppTheme.error;
        statusIcon = Icons.error;
        statusText = 'Not Found';
      case _ScanStatus.ambiguous:
        statusColor = AppTheme.accent;
        statusIcon = Icons.help;
        statusText = 'Multi-Match';
      case _ScanStatus.error:
        statusColor = AppTheme.error;
        statusIcon = Icons.wifi_off;
        statusText = 'Error';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.darkCard.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(statusIcon, color: statusColor, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(scan.barcode, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  if (scan.productName != null)
                    Text('${scan.productName} → ${scan.customerName}',
                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  if (scan.errorMsg != null)
                    Text(scan.errorMsg!, style: const TextStyle(color: AppTheme.error, fontSize: 12)),
                ],
              ),
            ),
            Text(statusText, style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
          if (scan.status == _ScanStatus.notFound) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 32,
              child: OutlinedButton.icon(
                onPressed: onLogOrphan,
                icon: const Icon(Icons.add_box_outlined, size: 16),
                label: const Text('Log as Orphan', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.warning,
                  side: BorderSide(color: AppTheme.warning.withValues(alpha: 0.5)),
                ),
              ),
            ),
          ],
          if (scan.status == _ScanStatus.ambiguous && scan.candidates != null) ...[
            const SizedBox(height: 8),
            ...scan.candidates!.map((c) => Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                const Icon(Icons.person_outline, size: 16, color: Colors.white54),
                const SizedBox(width: 6),
                Text('${c['customer_name']} — ${c['product_name']}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ]),
            )),
          ],
        ],
      ),
    );
  }
}
