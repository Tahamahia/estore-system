import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

enum InvoiceMode { customer, merchant }

class InvoiceGenerator {
  static String _translateStatus(String status) {
    switch (status) {
      case 'pending': return 'في انتظار الشراء';
      case 'purchased': return 'تم الشراء';
      case 'shipped': return 'تم الشحن';
      case 'arrived_warehouse': return 'وصل المخزن';
      case 'sorted': return 'تم الفرز';
      case 'ready_dispatch': return 'جاهز للتوصيل';
      case 'dispatched': return 'في الطريق';
      case 'delivered': return 'تم التوصيل';
      case 'cancelled': return 'ملغي';
      case 'refunded': return 'مُسترد';
      case 'transferred_to_inventory': return 'محوّل للمخزون';
      case 'in_stock': return 'فوري';
      default: return status;
    }
  }

  /// Returns the PDF as bytes. Callers are responsible for displaying/printing it.
  static Future<Uint8List> generate({
    required Map<String, dynamic> order,
    required List<dynamic> items,
    required InvoiceMode mode,
  }) async {
    // Load Arabic fonts — Cairo supports proper Arabic shaping
    final font = await PdfGoogleFonts.cairoRegular();
    final fontBold = await PdfGoogleFonts.cairoBold();

    final customerName = order['customer_name'] as String? ?? 'غير معروف';
    final phone = order['customer_phone'] as String? ?? '';
    final orderStatus = order['status'] as String? ?? '';
    final createdAt = order['created_at'] as String? ?? '';
    final rawId = order['id'] as String? ?? '';
    final shortId = rawId.length >= 8
        ? rawId.substring(0, 8).toUpperCase()
        : rawId.toUpperCase();

    double itemsCostUsd = 0;
    double shippingUsd = 0;
    double totalLocal = 0;
    for (final raw in items) {
      final item = raw as Map<String, dynamic>;
      if ((item['status'] as String?) == 'cancelled') continue;
      final qty = (item['quantity'] as num?)?.toInt() ?? 1;
      final itemShippingRate = (item['shipping_rate_per_kg'] as num?)?.toDouble() ?? 0;
      itemsCostUsd += ((item['unit_price_foreign'] as num?)?.toDouble() ?? 0) * qty;
      shippingUsd += ((item['weight'] as num?)?.toDouble() ?? 0) * itemShippingRate * qty;
      totalLocal += ((item['unit_price_local'] as num?)?.toDouble() ?? 0) * qty;
    }
    final totalUnits = items.fold<int>(
      0,
      (sum, raw) => sum + (((raw as Map<String, dynamic>)['quantity'] as num?)?.toInt() ?? 1),
    );

    // Applying ThemeData with Arabic font ensures every pw.Text in the document
    // inherits the Cairo font, which is required for proper Arabic glyph shaping.
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: font, bold: fontBold),
    );

    final baseStyle = pw.TextStyle(font: font, fontSize: 11);
    final boldStyle = pw.TextStyle(font: fontBold, fontSize: 11);

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      textDirection: pw.TextDirection.rtl,
      margin: const pw.EdgeInsets.all(32),
      build: (pw.Context ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          // ── Header bar ──────────────────────────────────────────
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const pw.BoxDecoration(
              color: PdfColor.fromInt(0xFF243150),
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      mode == InvoiceMode.customer ? 'فاتورة' : 'نسخة التاجر',
                      style: pw.TextStyle(font: fontBold, fontSize: 18, color: PdfColors.white),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      'طلب رقم: #$shortId',
                      style: pw.TextStyle(font: font, fontSize: 11, color: PdfColors.grey300),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    if (createdAt.length >= 10)
                      pw.Text(
                        createdAt.substring(0, 10),
                        style: pw.TextStyle(font: font, fontSize: 11, color: PdfColors.grey300),
                      ),
                    pw.Text(
                      _translateStatus(orderStatus),
                      style: pw.TextStyle(font: fontBold, fontSize: 11, color: PdfColors.grey300),
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 14),

          // ── Customer info ────────────────────────────────────────
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('معلومات الزبون', style: boldStyle),
                pw.SizedBox(height: 6),
                pw.Text('الاسم: $customerName', style: baseStyle),
                if (phone.isNotEmpty) pw.Text('الهاتف: $phone', style: baseStyle),
              ],
            ),
          ),
          pw.SizedBox(height: 14),

          // ── Items table ──────────────────────────────────────────
          pw.Text('تفاصيل المنتجات ($totalUnits قطعة)', style: pw.TextStyle(font: fontBold, fontSize: 12)),
          pw.SizedBox(height: 6),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            // Customer: Product(flex) | Qty(36) | Price(90) | Total(90)
            // Merchant: Product(flex) | Qty(36) | Cost$(72) | Shipping$(72) | Selling(72) | Total(72)
            columnWidths: mode == InvoiceMode.customer
                ? {
                    0: const pw.FlexColumnWidth(1),
                    1: const pw.FixedColumnWidth(36),
                    2: const pw.FixedColumnWidth(90),
                    3: const pw.FixedColumnWidth(90),
                  }
                : {
                    0: const pw.FlexColumnWidth(1),
                    1: const pw.FixedColumnWidth(36),
                    2: const pw.FixedColumnWidth(64),
                    3: const pw.FixedColumnWidth(64),
                    4: const pw.FixedColumnWidth(64),
                    5: const pw.FixedColumnWidth(64),
                  },
            children: [
              // Header row
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _cell('المنتج', boldStyle),
                  _cell('الكمية', boldStyle),
                  if (mode == InvoiceMode.merchant) ...[
                    _cell('التكلفة \$', boldStyle),
                    _cell('الشحن \$', boldStyle),
                  ],
                  _cell('السعر (د.ل)', boldStyle),
                  _cell('الإجمالي (د.ل)', boldStyle),
                ],
              ),
              // Data rows
              ...items.map((raw) {
                final item = raw as Map<String, dynamic>;
                final name = item['product_name'] as String? ?? 'منتج';
                final qty = (item['quantity'] as num?)?.toInt() ?? 1;
                final size = item['size'] as String?;
                final color = item['color'] as String?;
                final sku = item['sku'] as String?;
                final unitLocal = (item['unit_price_local'] as num?)?.toDouble() ?? 0;
                final unitForeign = (item['unit_price_foreign'] as num?)?.toDouble() ?? 0;
                // Per-unit shipping = weight × rate.
                final weight = (item['weight'] as num?)?.toDouble() ?? 0;
                final shippingRate = (item['shipping_rate_per_kg'] as num?)?.toDouble() ?? 0;
                final unitShipping = weight * shippingRate;
                final isCancelled = (item['status'] as String?) == 'cancelled';
                final lineTotal = unitLocal > 0 ? (unitLocal * qty).toStringAsFixed(0) : '-';

                final descParts = [
                  name,
                  if (size != null && size.isNotEmpty) 'المقاس: $size',
                  if (color != null && color.isNotEmpty) 'اللون: $color',
                  if (sku != null && sku.isNotEmpty) 'SKU: $sku',
                  if (isCancelled) '(ملغي)',
                ];
                final desc = descParts.join(' | ');

                final cellStyle = isCancelled
                    ? pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey500)
                    : pw.TextStyle(font: font, fontSize: 10);

                return pw.TableRow(children: [
                  _cell(desc, cellStyle),
                  _cell('$qty', cellStyle),
                  if (mode == InvoiceMode.merchant) ...[
                    _cell('\$${unitForeign.toStringAsFixed(2)}', cellStyle),
                    _cell('\$${unitShipping.toStringAsFixed(2)}', cellStyle),
                  ],
                  _cell(unitLocal > 0 ? unitLocal.toStringAsFixed(0) : '-', cellStyle),
                  _cell(lineTotal, cellStyle),
                ]);
              }),
            ],
          ),
          pw.SizedBox(height: 14),

          // ── Totals block ─────────────────────────────────────────
          pw.Align(
            alignment: pw.Alignment.centerLeft,
            child: pw.Container(
              width: 230,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  if (mode == InvoiceMode.merchant) ...[
                    _totalRow('تكلفة البضاعة', '\$${itemsCostUsd.toStringAsFixed(2)}', baseStyle),
                    if (shippingUsd > 0)
                      _totalRow('تكلفة الشحن', '\$${shippingUsd.toStringAsFixed(2)}', baseStyle),
                    pw.Divider(height: 1, color: PdfColors.grey400),
                    pw.SizedBox(height: 4),
                  ],
                  _totalRow(
                    'الإجمالي',
                    '${totalLocal.toStringAsFixed(0)} د.ل',
                    pw.TextStyle(font: fontBold, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),

          pw.Spacer(),
          pw.Divider(color: PdfColors.grey300),
          pw.SizedBox(height: 6),
          pw.Text(
            mode == InvoiceMode.customer
                ? 'شكراً لتسوقك معنا'
                : 'وثيقة داخلية — للتاجر فقط',
            style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey500),
            textAlign: pw.TextAlign.center,
          ),
        ],
      ),
    ));

    return doc.save();
  }

  static pw.Widget _cell(String text, pw.TextStyle style) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
        child: pw.Text(text, style: style),
      );

  static pw.Widget _totalRow(String label, String value, pw.TextStyle style) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label, style: style),
            pw.Text(value, style: style),
          ],
        ),
      );
}
