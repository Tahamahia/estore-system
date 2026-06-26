import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:estore_app/app/theme.dart';

/// Warehouse Scanning Screen
/// Uses RawKeyboardListener / HardwareKeyboard for barcode scanner input
/// without requiring text field focus.
class ScanningScreen extends StatefulWidget {
  const ScanningScreen({super.key});

  @override
  State<ScanningScreen> createState() => _ScanningScreenState();
}

class _ScanningScreenState extends State<ScanningScreen> {
  final FocusNode _focusNode = FocusNode();
  String _buffer = '';
  DateTime _lastKeyTime = DateTime.now();
  String? _lastScannedCode;
  final List<_ScanResult> _scanHistory = [];

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    final now = DateTime.now();
    // If more than 100ms between keystrokes, reset buffer (manual typing vs scanner)
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

  void _processBarcode(String barcode) {
    setState(() {
      _lastScannedCode = barcode;
      _scanHistory.insert(0, _ScanResult(
        barcode: barcode,
        timestamp: DateTime.now(),
        status: _ScanStatus.processing,
      ));
    });

    // Simulate API call
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          if (_scanHistory.isNotEmpty) {
            _scanHistory[0] = _scanHistory[0].copyWith(
              status: _ScanStatus.found,
              customerName: 'Ahmed Ali',
              productName: 'Nike Air Max 90',
            );
          }
        });
      }
    });
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
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primary.withValues(alpha: 0.2),
                      AppTheme.secondary.withValues(alpha: 0.1),
                    ],
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
                          Row(
                            children: [
                              Container(
                                width: 8, height: 8,
                                decoration: const BoxDecoration(color: AppTheme.success, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 8),
                              const Text('Scanner Ready', style: TextStyle(color: AppTheme.success, fontWeight: FontWeight.w600)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Scan any barcode or QR code — input is captured automatically',
                            style: TextStyle(color: Colors.white54, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    if (_lastScannedCode != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.darkCard,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          children: [
                            const Text('Last Scan', style: TextStyle(color: Colors.white38, fontSize: 11)),
                            const SizedBox(height: 2),
                            Text(_lastScannedCode!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Manual entry + scan history
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

  Widget _buildScanHistory() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const Text('Scan History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                const Spacer(),
                Text('${_scanHistory.length} scans', style: const TextStyle(color: Colors.white38, fontSize: 13)),
              ],
            ),
          ),
          const Divider(height: 1, color: AppTheme.darkBorder),
          Expanded(
            child: _scanHistory.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.qr_code, size: 48, color: Colors.white24),
                        SizedBox(height: 12),
                        Text('No scans yet', style: TextStyle(color: Colors.white38)),
                        Text('Scan a barcode to begin', style: TextStyle(color: Colors.white24, fontSize: 13)),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _scanHistory.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final scan = _scanHistory[index];
                      return _ScanTile(scan: scan);
                    },
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
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Manual Entry', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
          const SizedBox(height: 16),
          TextField(
            decoration: const InputDecoration(
              hintText: 'Enter barcode manually...',
              hintStyle: TextStyle(color: Colors.white38),
              prefixIcon: Icon(Icons.keyboard, color: Colors.white38),
            ),
            style: const TextStyle(color: Colors.white),
            onSubmitted: (value) {
              if (value.isNotEmpty) _processBarcode(value);
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.inventory_2_outlined, size: 20),
              label: const Text('Log Orphaned Package'),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.warning),
            ),
          ),
        ],
      ),
    );
  }
}

enum _ScanStatus { processing, found, notFound, ambiguous }

class _ScanResult {
  final String barcode;
  final DateTime timestamp;
  final _ScanStatus status;
  final String? customerName;
  final String? productName;

  _ScanResult({
    required this.barcode,
    required this.timestamp,
    required this.status,
    this.customerName,
    this.productName,
  });

  _ScanResult copyWith({_ScanStatus? status, String? customerName, String? productName}) {
    return _ScanResult(
      barcode: barcode,
      timestamp: timestamp,
      status: status ?? this.status,
      customerName: customerName ?? this.customerName,
      productName: productName ?? this.productName,
    );
  }
}

class _ScanTile extends StatelessWidget {
  final _ScanResult scan;
  const _ScanTile({required this.scan});

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
        break;
      case _ScanStatus.found:
        statusColor = AppTheme.success;
        statusIcon = Icons.check_circle;
        statusText = 'Found';
        break;
      case _ScanStatus.notFound:
        statusColor = AppTheme.error;
        statusIcon = Icons.error;
        statusText = 'Not Found';
        break;
      case _ScanStatus.ambiguous:
        statusColor = AppTheme.accent;
        statusIcon = Icons.help;
        statusText = 'Multiple Matches';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.darkCard.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(statusIcon, color: statusColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(scan.barcode, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                if (scan.productName != null)
                  Text('${scan.productName} → ${scan.customerName}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
          Text(statusText, style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
