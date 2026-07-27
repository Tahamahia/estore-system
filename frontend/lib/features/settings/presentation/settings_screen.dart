import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:estore_app/app/theme.dart';
import 'package:estore_app/core/providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(shippingSourcesProvider.notifier).fetchSources());
  }

  void _showAddDialog() {
    showDialog(context: context, builder: (_) => _SourceDialog(
      onSave: (name, rate) async {
        await ref.read(shippingSourcesProvider.notifier).createSource(name, rate);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('✅ تم إضافة "$name"'),
            backgroundColor: AppTheme.success,
          ));
        }
      },
    ));
  }

  void _showEditDialog(Map<String, dynamic> source) {
    showDialog(context: context, builder: (_) => _SourceDialog(
      initialName: source['name'] as String,
      initialRate: (source['rate_per_kg'] as num).toDouble(),
      onSave: (name, rate) async {
        await ref.read(shippingSourcesProvider.notifier).updateSource(
          (source['id'] as num).toInt(), name, rate,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('✅ تم تحديث "$name"'),
            backgroundColor: AppTheme.success,
          ));
        }
      },
    ));
  }

  void _confirmDelete(Map<String, dynamic> source) {
    final name = source['name'] as String;
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: AppTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('تأكيد الحذف', style: TextStyle(color: Colors.white)),
      content: Text('هل تريد حذف "$name"؟ لا يمكن التراجع عن هذا الإجراء.',
        style: const TextStyle(color: Colors.white70)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
        ),
        ElevatedButton(
          onPressed: () async {
            Navigator.of(context).pop();
            await ref.read(shippingSourcesProvider.notifier).deleteSource(
              (source['id'] as num).toInt(),
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('تم حذف "$name"'),
                backgroundColor: AppTheme.error,
              ));
            }
          },
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
          child: const Text('حذف'),
        ),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(shippingSourcesProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('الضبط', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white)),
            const Spacer(),
          ]),
          const SizedBox(height: 24),

          // ── Shipping Sources Section ────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.darkSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.darkBorder),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.language_outlined, color: AppTheme.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                  Text('مواقع الشراء', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                  Text('سعر الشحن لكل كيلو (\$) بحسب الموقع', style: TextStyle(color: Colors.white54, fontSize: 12)),
                ]),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: _showAddDialog,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('إضافة موقع'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              state.when(
                loading: () => const Center(child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                )),
                error: (e, _) => Center(child: Text('فشل تحميل المواقع: $e',
                  style: const TextStyle(color: AppTheme.error))),
                data: (sources) {
                  if (sources.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('لا توجد مواقع مضافة بعد', style: TextStyle(color: Colors.white38)),
                      ),
                    );
                  }
                  return Column(
                    children: sources.map((source) => _SourceTile(
                      source: source,
                      onEdit: () => _showEditDialog(source),
                      onDelete: () => _confirmDelete(source),
                    )).toList(),
                  );
                },
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  final Map<String, dynamic> source;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _SourceTile({required this.source, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final name = source['name'] as String;
    final rate = (source['rate_per_kg'] as num).toDouble();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.secondary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.storefront_outlined, color: AppTheme.secondary, size: 18),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
          Text('\$${rate.toStringAsFixed(2)} / كيلو', style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ])),
        IconButton(
          icon: const Icon(Icons.edit_outlined, color: Colors.white54, size: 20),
          onPressed: onEdit,
          tooltip: 'تعديل',
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline, color: AppTheme.error, size: 20),
          onPressed: onDelete,
          tooltip: 'حذف',
        ),
      ]),
    );
  }
}

class _SourceDialog extends StatefulWidget {
  final String? initialName;
  final double? initialRate;
  final Future<void> Function(String name, double rate) onSave;
  const _SourceDialog({this.initialName, this.initialRate, required this.onSave});

  @override
  State<_SourceDialog> createState() => _SourceDialogState();
}

class _SourceDialogState extends State<_SourceDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _rateCtrl;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName ?? '');
    _rateCtrl = TextEditingController(
      text: widget.initialRate != null ? widget.initialRate!.toString() : '',
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _rateCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initialName != null;

    return Dialog(
      backgroundColor: AppTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              isEdit ? 'تعديل موقع الشراء' : 'إضافة موقع شراء',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
            ),
            const SizedBox(height: 20),
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: AppTheme.error.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                child: Text(_error!, style: const TextStyle(color: AppTheme.error, fontSize: 13)),
              ),
            ],
            TextField(
              controller: _nameCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'اسم الموقع *',
                hintText: 'مثال: Shein',
                hintStyle: TextStyle(color: Colors.white24),
                prefixIcon: Icon(Icons.language_outlined),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _rateCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'سعر الشحن للكيلو (\$) *',
                hintText: 'مثال: 8.5',
                hintStyle: TextStyle(color: Colors.white24),
                prefixIcon: Icon(Icons.scale_outlined),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(height: 48, child: ElevatedButton.icon(
              onPressed: _saving ? null : () async {
                final name = _nameCtrl.text.trim();
                final rate = double.tryParse(_rateCtrl.text.trim());
                if (name.isEmpty) { setState(() => _error = 'اسم الموقع مطلوب'); return; }
                if (rate == null || rate < 0) { setState(() => _error = 'سعر الشحن يجب أن يكون رقماً موجباً'); return; }
                setState(() { _saving = true; _error = null; });
                await widget.onSave(name, rate);
                if (mounted) Navigator.of(context).pop();
              },
              icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_rounded, size: 20),
              label: Text(_saving ? 'جاري الحفظ...' : (isEdit ? 'حفظ التغييرات' : 'إضافة')),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            )),
          ]),
        ),
      ),
    );
  }
}
