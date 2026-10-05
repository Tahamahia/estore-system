import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:estore_app/app/theme.dart';

/// Paper the bag label is printed on. Stored per device in shared_preferences
/// (the label printer is attached to the device, not the tenant).
enum LabelPageSize {
  label100x150('ملصق 100×150 مم'),
  roll80('رول حراري 80 مم'),
  a6('A6');

  final String label;
  const LabelPageSize(this.label);

  PdfPageFormat get format {
    const mm = PdfPageFormat.mm;
    switch (this) {
      case LabelPageSize.label100x150:
        return const PdfPageFormat(100 * mm, 150 * mm, marginAll: 4 * mm);
      case LabelPageSize.roll80:
        return const PdfPageFormat(80 * mm, double.infinity, marginAll: 3 * mm);
      case LabelPageSize.a6:
        return const PdfPageFormat(105 * mm, 148 * mm, marginAll: 5 * mm);
    }
  }
}

/// Bag labels (one per order, price-free except the amount to collect) and
/// the A4 manifest handover sheet. Data comes from GET /orders/:id/label,
/// which the sorter can read — never from the priced order endpoints.
class LabelGenerator {
  static const _kSizeKey = 'label_page_size';

  static Future<LabelPageSize> loadPageSize() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_kSizeKey);
    return LabelPageSize.values.firstWhere(
      (s) => s.name == name,
      orElse: () => LabelPageSize.label100x150,
    );
  }

  static Future<void> savePageSize(LabelPageSize size) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSizeKey, size.name);
  }

  static Future<Map<String, dynamic>> fetchLabel(Dio dio, String orderId) async {
    final res = await dio.get('/orders/$orderId/label');
    return Map<String, dynamic>.from(res.data as Map);
  }

  static Future<List<Map<String, dynamic>>> fetchLabels(Dio dio, List<String> orderIds) =>
      Future.wait(orderIds.map((id) => fetchLabel(dio, id)));

  static String shortId(String id) => (id.length > 8 ? id.substring(0, 8) : id).toUpperCase();

  static String _money(num v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  static String _now() {
    final d = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  static String _joinNonEmpty(List<Object?> parts, String sep) =>
      parts.map((p) => (p as String?)?.trim() ?? '').where((p) => p.isNotEmpty).join(sep);

  static Future<pw.ThemeData> _theme() async => pw.ThemeData.withFont(
        base: await PdfGoogleFonts.cairoRegular(),
        bold: await PdfGoogleFonts.cairoBold(),
      );

  static Future<pw.MemoryImage?> _logo() async {
    try {
      final data = await rootBundle.load('assets/images/mukhmal-logo.png');
      return pw.MemoryImage(data.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  /// One label per page, one page per order.
  static Future<Uint8List> buildLabels(List<Map<String, dynamic>> labels, LabelPageSize size) async {
    final format = size.format;
    final doc = pw.Document(theme: await _theme());
    final logo = await _logo();
    // Type scale relative to the 100 mm label's printable width.
    final k = format.availableWidth / (92 * PdfPageFormat.mm);
    final printedAt = _now();

    for (final l in labels) {
      doc.addPage(pw.Page(
        pageFormat: format,
        textDirection: pw.TextDirection.rtl,
        build: (_) => _label(l, k, logo, printedAt),
      ));
    }
    return doc.save();
  }

  static pw.Widget _label(Map<String, dynamic> l, double k, pw.MemoryImage? logo, String printedAt) {
    final id = l['id'] as String? ?? '';
    final amount = (l['amount_to_collect'] as num?) ?? 0;
    final pieces = (l['item_count'] as num?)?.toInt() ?? 0;
    final phones = _joinNonEmpty([l['phone'], l['phone2']], '  /  ');
    final address = _joinNonEmpty([l['city'], l['area'], l['street']], ' · ');
    final carrier = _joinNonEmpty([
      l['delivery_company'],
      if (((l['driver_name'] as String?) ?? '').trim().isNotEmpty) 'المندوب: ${l['driver_name']}',
    ], ' — ');
    final divider = pw.Divider(height: 8 * k, thickness: 0.8, color: PdfColors.grey600);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        // Brand
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.center, children: [
          if (logo != null) pw.Image(logo, width: 22 * k, height: 22 * k),
          if (logo != null) pw.SizedBox(width: 6 * k),
          pw.Text('مخمل', style: pw.TextStyle(fontSize: 16 * k, fontWeight: pw.FontWeight.bold)),
        ]),
        divider,
        // Order id + QR of the full id
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('رقم الطلب', style: pw.TextStyle(fontSize: 9 * k, color: PdfColors.grey700)),
              pw.Text('#${shortId(id)}',
                  textDirection: pw.TextDirection.ltr,
                  style: pw.TextStyle(fontSize: 22 * k, fontWeight: pw.FontWeight.bold, letterSpacing: 1)),
            ]),
          ),
          pw.BarcodeWidget(
            barcode: pw.Barcode.qrCode(),
            data: id,
            width: 62 * k,
            height: 62 * k,
            drawText: false,
          ),
        ]),
        divider,
        // Customer
        pw.Text(l['full_name'] as String? ?? '—',
            style: pw.TextStyle(fontSize: 15 * k, fontWeight: pw.FontWeight.bold)),
        if (phones.isNotEmpty)
          pw.Text(phones, textDirection: pw.TextDirection.ltr, textAlign: pw.TextAlign.right,
              style: pw.TextStyle(fontSize: 13 * k, fontWeight: pw.FontWeight.bold)),
        if (address.isNotEmpty) pw.Text(address, style: pw.TextStyle(fontSize: 11 * k)),
        pw.SizedBox(height: 4 * k),
        pw.Text('عدد القطع: $pieces', style: pw.TextStyle(fontSize: 12 * k, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6 * k),
        // Amount to collect — the one number the driver needs
        pw.Container(
          padding: pw.EdgeInsets.symmetric(vertical: 6 * k, horizontal: 6 * k),
          decoration: pw.BoxDecoration(border: pw.Border.all(width: 2)),
          child: amount > 0
              ? pw.Column(children: [
                  pw.Text('المبلغ المطلوب تحصيله', style: pw.TextStyle(fontSize: 10 * k)),
                  pw.Text('${_money(amount)} د.ل',
                      style: pw.TextStyle(fontSize: 34 * k, fontWeight: pw.FontWeight.bold)),
                ])
              : pw.Center(
                  child: pw.Text('مدفوع مسبقاً',
                      style: pw.TextStyle(fontSize: 26 * k, fontWeight: pw.FontWeight.bold)),
                ),
        ),
        if (carrier.isNotEmpty) ...[
          pw.SizedBox(height: 6 * k),
          pw.Text(carrier, style: pw.TextStyle(fontSize: 10 * k)),
        ],
        pw.SizedBox(height: 4 * k),
        pw.Text('طُبع: $printedAt', textDirection: pw.TextDirection.rtl,
            style: pw.TextStyle(fontSize: 8 * k, color: PdfColors.grey700)),
      ],
    );
  }

  /// A4 handover sheet: what the driver leaves with and must bring back.
  static Future<Uint8List> buildManifestSheet({
    required Map<String, dynamic> manifest,
    required List<Map<String, dynamic>> labels,
  }) async {
    final doc = pw.Document(theme: await _theme());
    final logo = await _logo();
    final company = manifest['delivery_company'] as String? ?? '—';
    final driver = (manifest['driver_name'] as String?)?.trim();
    final total = labels.fold<num>(0, (sum, l) => sum + ((l['amount_to_collect'] as num?) ?? 0));
    final pieces = labels.fold<int>(0, (sum, l) => sum + ((l['item_count'] as num?)?.toInt() ?? 0));
    final head = pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold);
    final cell = pw.TextStyle(fontSize: 10);

    pw.Widget c(String text, pw.TextStyle style, {bool ltr = false}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: pw.Text(text, style: style,
              textDirection: ltr ? pw.TextDirection.ltr : null),
        );

    pw.Widget signature(String label) => pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.SizedBox(height: 36),
            pw.Container(height: 0.8, color: PdfColors.black),
            pw.SizedBox(height: 4),
            pw.Text(label, style: head),
          ]),
        );

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      textDirection: pw.TextDirection.rtl,
      margin: const pw.EdgeInsets.all(28),
      header: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        pw.Row(children: [
          if (logo != null) pw.Image(logo, width: 30, height: 30),
          if (logo != null) pw.SizedBox(width: 8),
          pw.Text('مخمل — كشف تسليم', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.Spacer(),
          pw.Text(_now(), style: cell),
        ]),
        pw.SizedBox(height: 6),
        pw.Text('شركة التوصيل: $company', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        if (driver != null && driver.isNotEmpty)
          pw.Text('المندوب: $driver', style: const pw.TextStyle(fontSize: 12)),
        pw.SizedBox(height: 10),
      ]),
      build: (_) => [
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.5),
          columnWidths: const {
            0: pw.FixedColumnWidth(70),
            1: pw.FlexColumnWidth(2),
            2: pw.FixedColumnWidth(90),
            3: pw.FlexColumnWidth(1.5),
            4: pw.FixedColumnWidth(40),
            5: pw.FixedColumnWidth(70),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                c('الطلب', head), c('الزبون', head), c('الهاتف', head),
                c('المنطقة', head), c('القطع', head), c('المطلوب (د.ل)', head),
              ],
            ),
            for (final l in labels)
              pw.TableRow(children: [
                c('#${shortId(l['id'] as String? ?? '')}', cell, ltr: true),
                c(l['full_name'] as String? ?? '—', cell),
                c(_joinNonEmpty([l['phone']], ''), cell, ltr: true),
                c(_joinNonEmpty([l['city'], l['area']], ' · '), cell),
                c('${(l['item_count'] as num?)?.toInt() ?? 0}', cell),
                c(((l['amount_to_collect'] as num?) ?? 0) > 0
                    ? _money((l['amount_to_collect'] as num?) ?? 0)
                    : 'مدفوع', cell),
              ]),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Row(children: [
          pw.Text('عدد الطلبات: ${labels.length}  ·  عدد القطع: $pieces', style: head),
          pw.Spacer(),
          pw.Text('إجمالي المطلوب تحصيله: ${_money(total)} د.ل',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        ]),
        pw.SizedBox(height: 30),
        pw.Row(children: [
          signature('توقيع المندوب'),
          pw.SizedBox(width: 40),
          signature('توقيع المستلم من المخزن'),
        ]),
      ],
    ));
    return doc.save();
  }

  /// Desktop: native print dialog. Mobile web: share/download the PDF.
  static Future<void> output(Uint8List bytes, String filename, {required bool mobile}) async {
    if (mobile) {
      await Printing.sharePdf(bytes: bytes, filename: filename);
    } else {
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: filename);
    }
  }

  /// Fetch, build and print one label per order (one per page).
  static Future<void> printLabels(Dio dio, List<String> orderIds, {required bool mobile}) async {
    if (orderIds.isEmpty) return;
    final labels = await fetchLabels(dio, orderIds);
    final bytes = await buildLabels(labels, await loadPageSize());
    final name = orderIds.length == 1 ? 'Label_${shortId(orderIds.first)}.pdf' : 'Labels_${orderIds.length}.pdf';
    await output(bytes, name, mobile: mobile);
  }

  static Future<void> printManifestSheet(
    Dio dio,
    Map<String, dynamic> manifest,
    List<String> orderIds, {
    required bool mobile,
  }) async {
    final labels = await fetchLabels(dio, orderIds);
    final bytes = await buildManifestSheet(manifest: manifest, labels: labels);
    await output(bytes, 'Manifest_${shortId(manifest['id'] as String? ?? '')}.pdf', mobile: mobile);
  }
}

/// Lets the user pick the label paper; persists the choice on this device.
Future<void> showLabelSizePicker(BuildContext context) async {
  final current = await LabelGenerator.loadPageSize();
  if (!context.mounted) return;
  final picked = await showDialog<LabelPageSize>(
    context: context,
    builder: (ctx) => SimpleDialog(
      backgroundColor: AppTheme.darkSurface,
      title: const Text('حجم ورق الواصل', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      children: [
        for (final size in LabelPageSize.values)
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(size),
            child: Row(children: [
              Icon(size == current ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: size == current ? AppTheme.primary : Colors.white38, size: 20),
              const SizedBox(width: 10),
              Text(size.label, style: const TextStyle(color: Colors.white)),
            ]),
          ),
      ],
    ),
  );
  if (picked != null) await LabelGenerator.savePageSize(picked);
}
