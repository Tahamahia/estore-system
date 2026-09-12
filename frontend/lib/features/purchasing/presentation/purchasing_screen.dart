import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:estore_app/app/theme.dart';
import 'package:estore_app/core/providers.dart';
import 'package:estore_app/core/utils/dialog_utils.dart';

/// Purchasing screen — replaces the nightly per-item dialog grind.
/// One row per pending item, grouped by order, with a per-order cart link,
/// an inline-editable table, and a single bulk save.
class PurchasingScreen extends ConsumerStatefulWidget {
  const PurchasingScreen({super.key});

  @override
  ConsumerState<PurchasingScreen> createState() => _PurchasingScreenState();
}

class _PurchasingScreenState extends ConsumerState<PurchasingScreen> {
  // Local edit buffer: itemId → mutable draft. Draft only exists after the row
  // has been touched, so `_drafts.length` == "rows changed".
  final Map<String, _ItemDraft> _drafts = {};
  // Per-item version snapshot from the last fetch (used to detect what the
  // server would see when we save).
  final Map<String, int> _versions = {};
  // Per-order source override (writes to orders.source_name on blur).
  final Map<String, String?> _orderSourceEdits = {};
  bool _markPurchased = true;
  String _sourceFilter = 'all';
  bool _saving = false;

  // Scanner support — matches scanning_screen.dart's pattern.
  final FocusNode _screenFocus = FocusNode();
  String _scanBuffer = '';
  DateTime _lastKey = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(purchasingProvider.notifier).fetchQueue();
      ref.read(shippingSourcesProvider.notifier).fetchSources();
    });
  }

  @override
  void dispose() {
    _screenFocus.dispose();
    for (final d in _drafts.values) {
      d.dispose();
    }
    super.dispose();
  }

  // ── Edit tracking ──────────────────────────────────────────

  _ItemDraft _draftFor(Map<String, dynamic> item, {double? inheritedRate}) {
    final id = item['id'] as String;
    _versions[id] = (item['version'] as num).toInt();
    return _drafts.putIfAbsent(id, () => _ItemDraft.fromItem(item, inheritedRate: inheritedRate));
  }

  void _markTouched() {
    if (!mounted) return;
    setState(() {});
  }

  // ── Barcode scanner: when a burst ends in Enter and a row's SKU field is
  // focused, we accept the burst into that field and advance focus to cost. ─
  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final now = DateTime.now();
    if (now.difference(_lastKey).inMilliseconds > 100) _scanBuffer = '';
    _lastKey = now;
    final focused = FocusManager.instance.primaryFocus;
    // Only auto-fill when a row's SKU field is focused (identified by
    // storing a debug label on the FocusNode).
    final label = focused?.debugLabel ?? '';
    if (!label.startsWith('sku:')) return;

    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_scanBuffer.isNotEmpty) {
        final itemId = label.substring('sku:'.length);
        final draft = _drafts[itemId];
        if (draft != null) {
          draft.skuCtrl.text = _scanBuffer;
          _markTouched();
          // Advance focus to the cost field.
          final costNode = draft.costFocus;
          FocusManager.instance.primaryFocus?.unfocus();
          FocusScope.of(context).requestFocus(costNode);
        }
        _scanBuffer = '';
      }
    } else {
      final char = event.character;
      if (char != null && char.isNotEmpty) _scanBuffer += char;
    }
  }

  // ── Save ───────────────────────────────────────────────────

  Future<void> _saveAll() async {
    if (_drafts.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      final items = <Map<String, dynamic>>[];
      for (final entry in _drafts.entries) {
        final d = entry.value;
        if (!d.isDirty) continue;
        final v = _versions[entry.key];
        if (v == null) continue;
        items.add(d.toPayload(id: entry.key, version: v));
      }
      if (items.isEmpty) {
        setState(() => _saving = false);
        return;
      }
      final result = await ref.read(purchasingProvider.notifier).savePurchases({
        'items': items,
        'mark_purchased': _markPurchased,
      });
      final updated = (result['updated'] as num?)?.toInt() ?? items.length;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('تم حفظ $updated قطعة'),
          backgroundColor: AppTheme.success,
        ));
      }
      // Drop only saved drafts; refetch to pull fresh versions.
      for (final it in items) {
        final draft = _drafts.remove(it['id']);
        draft?.dispose();
      }
      await ref.read(purchasingProvider.notifier).fetchQueue();
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final data = e.response?.data;
      if (status == 409) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('تغيّرت البيانات، تم إعادة التحميل'),
            backgroundColor: AppTheme.warning,
          ));
        }
        // Keep drafts so the user doesn't lose typing on other rows.
        await ref.read(purchasingProvider.notifier).fetchQueue();
      } else {
        final msg = data is Map<String, dynamic>
            ? (data['message'] as String? ?? data['error'] as String? ?? 'فشل الحفظ')
            : 'فشل الحفظ';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(msg),
            backgroundColor: AppTheme.error,
          ));
        }
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _launchCart(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _setOrderSource(String orderId, String? source, double? rate) async {
    // 1. Persist on the order.
    try {
      await ref.read(ordersProvider.notifier).updateOrder(orderId, {
        'version': _orderVersionMap[orderId] ?? 1,
        'source_name': source,
      });
    } catch (_) {
      // Non-fatal — the item-level writes still happen when the user saves.
    }
    // 2. Pre-fill every draft on this order.
    final data = ref.read(purchasingProvider).valueOrNull;
    if (data == null) return;
    final order = (data['orders'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .firstWhere((o) => o['order_id'] == orderId, orElse: () => {});
    for (final item in (order['items'] as List<dynamic>? ?? [])) {
      final it = item as Map<String, dynamic>;
      final inherited = (it['source_name'] as String?) ?? source;
      final draft = _draftFor(it, inheritedRate: rate);
      if (source != null) draft.sourceName = source;
      if (rate != null && draft.rateCtrl.text.trim().isEmpty) {
        draft.rateCtrl.text = rate.toStringAsFixed(2);
      }
      // Suppress "unused" warning on inherited — kept for future logic clarity.
      // ignore: unused_local_variable
      final _ = inherited;
    }
    _orderSourceEdits[orderId] = source;
    _markTouched();
  }

  // Cheap cache of order versions (not returned by /purchase-queue but the
  // PATCH /orders/:id needs one). Fall back to 1; if it's stale the server
  // returns 409 and we simply refetch.
  final Map<String, int> _orderVersionMap = {};

  // ── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mobile = isMobile(context);
    final queueState = ref.watch(purchasingProvider);
    final sourcesState = ref.watch(shippingSourcesProvider);
    final sources = sourcesState.valueOrNull ?? const [];

    return KeyboardListener(
      focusNode: _screenFocus,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Scaffold(
        backgroundColor: AppTheme.darkBg,
        body: SafeArea(
          child: queueState.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off, color: AppTheme.error, size: 48),
                  const SizedBox(height: 12),
                  Text('$e', style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () => ref.read(purchasingProvider.notifier).fetchQueue(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
            data: (data) {
              final orders = (data['orders'] as List<dynamic>? ?? [])
                  .cast<Map<String, dynamic>>();
              final totals = data['totals'] as Map<String, dynamic>? ?? const {};
              final filtered = _sourceFilter == 'all'
                  ? orders
                  : orders.where((o) {
                      final src = (o['source_name'] as String?) ?? '';
                      final items = o['items'] as List<dynamic>? ?? const [];
                      final anyItemHas = items.any((i) =>
                          ((i as Map<String, dynamic>)['source_name'] as String?) == _sourceFilter);
                      return src == _sourceFilter || anyItemHas;
                    }).toList();

              return Column(
                children: [
                  _buildHeader(totals, sources, mobile),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(
                            child: Text('لا توجد قطع بانتظار الشراء',
                                style: TextStyle(color: Colors.white38, fontSize: 15)))
                        : ListView.separated(
                            padding: EdgeInsets.fromLTRB(
                                mobile ? 12 : 24, 12, mobile ? 12 : 24, 90),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (_, i) => _OrderCard(
                              order: filtered[i],
                              sources: sources,
                              draftFor: _draftFor,
                              onDraftChanged: _markTouched,
                              onLaunchCart: _launchCart,
                              onSourceChanged: (src, rate) =>
                                  _setOrderSource(filtered[i]['order_id'] as String, src, rate),
                              mobile: mobile,
                            ),
                          ),
                  ),
                ],
              );
            },
          ),
        ),
        bottomSheet: _buildSaveBar(mobile),
      ),
    );
  }

  Widget _buildHeader(Map<String, dynamic> totals, List<Map<String, dynamic>> sources, bool mobile) {
    final ordersCount = (totals['orders'] as num?)?.toInt() ?? 0;
    final itemsCount = (totals['items'] as num?)?.toInt() ?? 0;

    return Padding(
      padding: EdgeInsets.fromLTRB(mobile ? 12 : 24, 12, mobile ? 12 : 24, 4),
      child: Row(children: [
        const Icon(Icons.shopping_cart_checkout, color: AppTheme.primary, size: 20),
        const SizedBox(width: 8),
        const Text('قائمة الشراء',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('$ordersCount طلبية · $itemsCount قطعة',
              style: const TextStyle(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        const Spacer(),
        SizedBox(
          width: mobile ? 140 : 200,
          child: DropdownButtonFormField<String>(
            initialValue: _sourceFilter,
            dropdownColor: AppTheme.darkCard,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: const InputDecoration(
              labelText: 'الموقع',
              isDense: true,
              prefixIcon: Icon(Icons.filter_list, size: 18),
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
            items: [
              const DropdownMenuItem(value: 'all', child: Text('الكل')),
              ...sources.map((s) => DropdownMenuItem(
                    value: s['name'] as String,
                    child: Text(s['name'] as String, overflow: TextOverflow.ellipsis),
                  )),
            ],
            onChanged: (v) => setState(() => _sourceFilter = v ?? 'all'),
          ),
        ),
      ]),
    );
  }

  Widget _buildSaveBar(bool mobile) {
    final dirtyCount = _drafts.values.where((d) => d.isDirty).length;
    final canSave = dirtyCount > 0 && !_saving;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: mobile ? 12 : 24, vertical: 10),
      decoration: const BoxDecoration(
        color: AppTheme.darkSurface,
        border: Border(top: BorderSide(color: AppTheme.darkBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Row(children: [
          Text('$dirtyCount قطعة معدّلة',
              style: TextStyle(color: canSave ? Colors.white70 : Colors.white38, fontSize: 13)),
          const SizedBox(width: 16),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Checkbox(
              value: _markPurchased,
              onChanged: (v) => setState(() => _markPurchased = v ?? true),
              activeColor: AppTheme.primary,
            ),
            const Text('تعليم كمُشتراة',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
          ]),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: canSave ? _saveAll : null,
            icon: _saving
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_rounded, size: 18),
            label: const Text('حفظ الكل'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ]),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// Per-order card
// ────────────────────────────────────────────────────────────

class _OrderCard extends StatefulWidget {
  final Map<String, dynamic> order;
  final List<Map<String, dynamic>> sources;
  final _ItemDraft Function(Map<String, dynamic> item, {double? inheritedRate}) draftFor;
  final VoidCallback onDraftChanged;
  final Future<void> Function(String url) onLaunchCart;
  final Future<void> Function(String? source, double? rate) onSourceChanged;
  final bool mobile;

  const _OrderCard({
    required this.order,
    required this.sources,
    required this.draftFor,
    required this.onDraftChanged,
    required this.onLaunchCart,
    required this.onSourceChanged,
    required this.mobile,
  });

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final orderId = order['order_id'] as String;
    final cartLink = order['cart_link'] as String? ?? '';
    final customer = order['customer_name'] as String? ?? '—';
    final phone = order['customer_phone'] as String? ?? '';
    final items = (order['items'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final orderSource = order['source_name'] as String?;
    final inheritedRate = _rateFor(orderSource);

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Icon(_expanded ? Icons.expand_less : Icons.expand_more, color: Colors.white54, size: 22),
              const SizedBox(width: 6),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(customer,
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('${phone.isNotEmpty ? '$phone · ' : ''}${items.length} قطع',
                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ]),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: cartLink.isEmpty ? null : () => widget.onLaunchCart(cartLink),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('فتح السلة', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ]),
          ),
        ),
        if (_expanded) ...[
          const Divider(height: 1, color: AppTheme.darkBorder),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              const Text('الموقع للطلبية:',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(width: 10),
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String?>(
                  initialValue: orderSource,
                  dropdownColor: AppTheme.darkCard,
                  isDense: true,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('— بدون —')),
                    ...widget.sources.map((s) => DropdownMenuItem<String?>(
                          value: s['name'] as String,
                          child: Text(
                            '${s['name']}  (\$${(s['rate_per_kg'] as num).toStringAsFixed(2)}/kg)',
                            overflow: TextOverflow.ellipsis,
                          ),
                        )),
                  ],
                  onChanged: (v) {
                    final rate = _rateFor(v);
                    widget.onSourceChanged(v, rate);
                  },
                ),
              ),
              const Spacer(),
              // Hidden field to keep the orderId reference visible in the tree
              // (helps debugging via Widget Inspector). Zero visual footprint.
              SizedBox(width: 0, child: Text(orderId, style: const TextStyle(fontSize: 0))),
            ]),
          ),
          const Divider(height: 1, color: AppTheme.darkBorder),
          // Items table (desktop) or compact rows (mobile)
          widget.mobile
              ? Column(children: [
                  for (final item in items)
                    _MobileItemRow(
                      item: item,
                      draft: widget.draftFor(item, inheritedRate: inheritedRate),
                      onChanged: widget.onDraftChanged,
                    ),
                ])
              : _DesktopItemTable(
                  items: items,
                  draftFor: (it) => widget.draftFor(it, inheritedRate: inheritedRate),
                  onChanged: widget.onDraftChanged,
                ),
        ],
      ]),
    );
  }

  double? _rateFor(String? sourceName) {
    if (sourceName == null) return null;
    for (final s in widget.sources) {
      if (s['name'] == sourceName) return (s['rate_per_kg'] as num).toDouble();
    }
    return null;
  }
}

// ────────────────────────────────────────────────────────────
// Desktop table
// ────────────────────────────────────────────────────────────

class _DesktopItemTable extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final _ItemDraft Function(Map<String, dynamic> item) draftFor;
  final VoidCallback onChanged;

  const _DesktopItemTable({
    required this.items,
    required this.draftFor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const headerStyle = TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        Row(children: const [
          Expanded(flex: 4, child: Text('اسم القطعة', style: headerStyle)),
          SizedBox(width: 48, child: Text('الكمية', style: headerStyle, textAlign: TextAlign.center)),
          Expanded(flex: 3, child: Text('الباركود', style: headerStyle)),
          Expanded(flex: 2, child: Text('التكلفة \$', style: headerStyle)),
          Expanded(flex: 2, child: Text('الوزن كغ', style: headerStyle)),
          SizedBox(width: 90, child: Text('الشحن \$', style: headerStyle, textAlign: TextAlign.end)),
        ]),
        const SizedBox(height: 6),
        const Divider(height: 1, color: AppTheme.darkBorder),
        for (final item in items) _DesktopItemRow(
          item: item,
          draft: draftFor(item),
          onChanged: onChanged,
        ),
      ]),
    );
  }
}

class _DesktopItemRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final _ItemDraft draft;
  final VoidCallback onChanged;

  const _DesktopItemRow({
    required this.item,
    required this.draft,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final qty = (item['quantity'] as num?)?.toInt() ?? 1;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(flex: 4, child: Text(
          item['product_name'] as String? ?? '—',
          style: const TextStyle(color: Colors.white, fontSize: 13),
          overflow: TextOverflow.ellipsis,
        )),
        SizedBox(width: 48, child: Text('$qty',
            style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center)),
        Expanded(flex: 3, child: _cell(draft.skuCtrl, focusNode: draft.skuFocus, onChanged: onChanged)),
        Expanded(flex: 2, child: _cell(draft.costCtrl, number: true, focusNode: draft.costFocus, onChanged: onChanged)),
        Expanded(flex: 2, child: _cell(draft.weightCtrl, number: true, focusNode: draft.weightFocus, onChanged: onChanged)),
        SizedBox(
          width: 90,
          child: ListenableBuilder(
            listenable: Listenable.merge([draft.costCtrl, draft.weightCtrl, draft.rateCtrl]),
            builder: (_, __) {
              final weight = double.tryParse(draft.weightCtrl.text.trim()) ?? 0;
              final rate = double.tryParse(draft.rateCtrl.text.trim()) ?? 0;
              final ship = weight * rate * qty;
              return Text(
                '\$${ship.toStringAsFixed(2)}',
                style: const TextStyle(color: AppTheme.secondary, fontSize: 12),
                textAlign: TextAlign.end,
              );
            },
          ),
        ),
      ]),
    );
  }

  Widget _cell(
    TextEditingController ctrl, {
    bool number = false,
    FocusNode? focusNode,
    required VoidCallback onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: TextField(
        controller: ctrl,
        focusNode: focusNode,
        keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
        inputFormatters: number
            ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))]
            : null,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        ),
        onChanged: (_) {
          draft.markDirty();
          onChanged();
        },
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// Mobile compact row
// ────────────────────────────────────────────────────────────

class _MobileItemRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final _ItemDraft draft;
  final VoidCallback onChanged;

  const _MobileItemRow({
    required this.item,
    required this.draft,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final qty = (item['quantity'] as num?)?.toInt() ?? 1;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(
            item['product_name'] as String? ?? '—',
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
          )),
          const SizedBox(width: 8),
          Text('×$qty', style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ]),
        const SizedBox(height: 6),
        LayoutBuilder(builder: (_, cons) {
          final wide = cons.maxWidth >= 400;
          final skuField = _tf(draft.skuCtrl, 'الباركود', focusNode: draft.skuFocus, onChanged: onChanged);
          final costField = _tf(draft.costCtrl, 'التكلفة \$', number: true, focusNode: draft.costFocus, onChanged: onChanged);
          final weightField = _tf(draft.weightCtrl, 'الوزن كغ', number: true, focusNode: draft.weightFocus, onChanged: onChanged);
          if (wide) {
            return Row(children: [
              Expanded(child: skuField),
              const SizedBox(width: 8),
              Expanded(child: costField),
              const SizedBox(width: 8),
              Expanded(child: weightField),
            ]);
          }
          return Column(children: [
            skuField,
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: costField),
              const SizedBox(width: 8),
              Expanded(child: weightField),
            ]),
          ]);
        }),
      ]),
    );
  }

  Widget _tf(TextEditingController ctrl, String label,
      {bool number = false, FocusNode? focusNode, required VoidCallback onChanged}) {
    return TextField(
      controller: ctrl,
      focusNode: focusNode,
      keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      inputFormatters:
          number ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))] : null,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      onChanged: (_) {
        draft.markDirty();
        onChanged();
      },
    );
  }
}

// ────────────────────────────────────────────────────────────
// Mutable per-item draft. Owns its own TextEditingControllers +
// FocusNodes so we can move focus programmatically for the scanner.
// ────────────────────────────────────────────────────────────

class _ItemDraft {
  final TextEditingController skuCtrl;
  final TextEditingController costCtrl;
  final TextEditingController weightCtrl;
  final TextEditingController rateCtrl;
  final FocusNode skuFocus;
  final FocusNode costFocus;
  final FocusNode weightFocus;
  String? sourceName;
  bool _dirty = false;

  _ItemDraft._({
    required this.skuCtrl,
    required this.costCtrl,
    required this.weightCtrl,
    required this.rateCtrl,
    required this.skuFocus,
    required this.costFocus,
    required this.weightFocus,
    required this.sourceName,
  });

  factory _ItemDraft.fromItem(Map<String, dynamic> item, {double? inheritedRate}) {
    final itemId = item['id'] as String;
    return _ItemDraft._(
      skuCtrl:    TextEditingController(text: (item['sku'] as String?) ?? ''),
      costCtrl:   TextEditingController(text: _numText(item['cost_usd'])),
      weightCtrl: TextEditingController(text: _numText(item['weight'])),
      rateCtrl:   TextEditingController(
          text: _numText(item['shipping_rate_per_kg'] ?? inheritedRate)),
      skuFocus:    FocusNode(debugLabel: 'sku:$itemId'),
      costFocus:   FocusNode(debugLabel: 'cost:$itemId'),
      weightFocus: FocusNode(debugLabel: 'weight:$itemId'),
      sourceName: item['source_name'] as String?,
    );
  }

  static String _numText(dynamic v) {
    if (v == null) return '';
    final n = (v is num) ? v : num.tryParse(v.toString());
    if (n == null || n == 0) return '';
    return n.toString();
  }

  bool get isDirty => _dirty;

  void markDirty() { _dirty = true; }

  Map<String, dynamic> toPayload({required String id, required int version}) {
    double? parseNum(String s) {
      final t = s.trim().replaceAll(',', '.');
      return t.isEmpty ? null : double.tryParse(t);
    }
    return {
      'id': id,
      'version': version,
      if (skuCtrl.text.trim().isNotEmpty) 'sku': skuCtrl.text.trim(),
      if (parseNum(costCtrl.text) != null) 'cost_usd': parseNum(costCtrl.text),
      if (parseNum(weightCtrl.text) != null) 'weight': parseNum(weightCtrl.text),
      if (sourceName != null) 'source_name': sourceName,
      if (parseNum(rateCtrl.text) != null) 'shipping_rate_per_kg': parseNum(rateCtrl.text),
    };
  }

  void dispose() {
    skuCtrl.dispose(); costCtrl.dispose(); weightCtrl.dispose(); rateCtrl.dispose();
    skuFocus.dispose(); costFocus.dispose(); weightFocus.dispose();
  }
}
