import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

enum InvoiceMode { customer, merchant }

class InvoiceGenerator {
  static String _translateStatus(String status) {
    switch (status) {
      case 'pending_payment': return 'في انتظار الدفع';
      case 'paid': return 'تم الدفع';
      case 'purchasing': return 'جاري الشراء';
      case 'purchased': return 'تم الشراء';
      case 'shipped': return 'تم الشحن';
      case 'arrived_warehouse': return 'وصل المخزن';
      case 'sorted': return 'تم الفرز';
      case 'ready_dispatch': return 'جاهز للتوصيل';
      case 'dispatched': return 'في الطريق';
      case 'delivered': return 'تم التوصيل';
      case 'cancelled': return 'ملغي';
      default: return status;
    }
  }

  static Future<void> print({
    required Map<String, dynamic> order,
    required List<dynamic> items,
    required InvoiceMode mode,
  }) async {
    final font = await PdfGoogleFonts.cairoRegular();
    final fontBold = await PdfGoogleFonts.cairoBold();

    final style = pw.TextStyle(font: font, fontSize: 11);
    final styleBold = pw.TextStyle(font: fontBold, fontSize: 11);

    final customerName = order['customer_name'] as String? ?? 'غير معروف';
    final phone = order['customer_phone'] as String? ?? '';
    final orderStatus = order['status'] as String? ?? '';
    final totalLocal = (order['total_local'] as num?)?.toDouble() ?? 0;
    final createdAt = order['created_at'] as String? ?? '';
    final rawId = order['id'] as String? ?? '';
    final shortId = rawId.length >= 8 ? rawId.substring(0, 8).toUpperCase() : rawId.toUpperCase();

    final shippingUsd = (order['shipping_cost_foreign'] as num?)?.toDouble() ?? 0;
    final rate = (order['pegged_exchange_rate'] as num?)?.toDouble() ?? 0;
    double itemsCostUsd = 0;
    for (final raw in items) {
      final item = raw as Map<String, dynamic>;
      if ((item['status'] as String?) == 'cancelled') continue;
      itemsCostUsd += ((item['unit_price_foreign'] as num?)?.toDouble() ?? 0) *
          ((item['quantity'] as num?)?.toInt() ?? 1);
    }
    final profit = (totalLocal > 0 && rate > 0)
        ? totalLocal - ((itemsCostUsd + shippingUsd) * rate)
        : null;

    final doc = pw.Document();

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      textDirection: pw.TextDirection.rtl,
      margin: const pw.EdgeInsets.all(32),
      build: (pw.Context context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          // Header bar
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
          pw.SizedBox(height: 16),

          // Customer info box
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('معلومات الزبون', style: styleBold),
                pw.SizedBox(height: 6),
                pw.Text('الاسم: $customerName', style: style),
                if (phone.isNotEmpty) pw.Text('الهاتف: $phone', style: style),
              ],
            ),
          ),
          pw.SizedBox(height: 16),

          // Items table
          pw.Text('تفاصيل المنتجات', style: pw.TextStyle(font: fontBold, fontSize: 12)),
          pw.SizedBox(height: 6),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            columnWidths: mode == InvoiceMode.customer
                ? {
                    0: const pw.FlexColumnWidth(4),
                    1: const pw.FixedColumnWidth(40),
                    2: const pw.FixedColumnWidth(80),
                    3: const pw.FixedColumnWidth(80),
                  }
                : {
                    0: const pw.FlexColumnWidth(3),
                    1: const pw.FixedColumnWidth(36),
                    2: const pw.FixedColumnWidth(60),
                    3: const pw.FixedColumnWidth(72),
                    4: const pw.FixedColumnWidth(72),
                  },
            children: [
              // Header row
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _cell('المنتج', styleBold),
                  _cell('الكمية', styleBold),
                  if (mode == InvoiceMode.merchant) _cell('التكلفة (\$)', styleBold),
                  _cell('سعر البيع (د.ع)', styleBold),
                  _cell('الإجمالي (د.ع)', styleBold),
                ],
              ),
              // Data rows
              ...items.map((raw) {
                final item = raw as Map<String, dynamic>;
                final name = item['product_name'] as String? ?? 'منتج';
                final qty = (item['quantity'] as num?)?.toInt() ?? 1;
                final size = item['size'] as String?;
                final color = item['color'] as String?;
                final unitLocal = (item['unit_price_local'] as num?)?.toDouble() ?? 0;
                final unitForeign = (item['unit_price_foreign'] as num?)?.toDouble() ?? 0;
                final isCancelled = (item['status'] as String?) == 'cancelled';
                final totalItem = unitLocal > 0 ? (unitLocal * qty).toStringAsFixed(0) : '-';
                final desc = [
                  name,
                  if (size != null && size.isNotEmpty) 'المقاس: $size',
                  if (color != null && color.isNotEmpty) 'اللون: $color',
                  if (isCancelled) '(ملغي)',
                ].join('  ');
                final cellStyle = isCancelled
                    ? pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey500)
                    : pw.TextStyle(font: font, fontSize: 10);
                return pw.TableRow(children: [
                  _cell(desc, cellStyle),
                  _cell('$qty', cellStyle),
                  if (mode == InvoiceMode.merchant)
                    _cell('\$${unitForeign.toStringAsFixed(2)}', cellStyle),
                  _cell(unitLocal > 0 ? unitLocal.toStringAsFixed(0) : '-', cellStyle),
                  _cell(totalItem, cellStyle),
                ]);
              }),
            ],
          ),
          pw.SizedBox(height: 16),

          // Totals block
          pw.Align(
            alignment: pw.Alignment.centerLeft,
            child: pw.Container(
              width: 220,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  if (mode == InvoiceMode.merchant) ...[
                    _totalRow('تكلفة البضاعة (\$)', '\$${itemsCostUsd.toStringAsFixed(2)}', style),
                    if (shippingUsd > 0)
                      _totalRow('تكلفة الشحن (\$)', '\$${shippingUsd.toStringAsFixed(2)}', style),
                    if (rate > 0)
                      _totalRow('سعر الصرف', '${rate.toStringAsFixed(2)} د.ع', style),
                    pw.Divider(height: 1, color: PdfColors.grey400),
                    pw.SizedBox(height: 4),
                  ],
                  _totalRow(
                    'الإجمالي',
                    '${totalLocal.toStringAsFixed(0)} د.ع',
                    pw.TextStyle(font: fontBold, fontSize: 13),
                  ),
                  if (mode == InvoiceMode.merchant && profit != null) ...[
                    pw.SizedBox(height: 4),
                    _totalRow(
                      'المكسب التقديري',
                      '${profit >= 0 ? '+' : ''}${profit.toStringAsFixed(0)} د.ع',
                      pw.TextStyle(
                        font: fontBold,
                        fontSize: 12,
                        color: profit >= 0 ? PdfColors.green700 : PdfColors.red700,
                      ),
                    ),
                  ],
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

    await Printing.layoutPdf(onLayout: (_) => doc.save());
  }

  static pw.Widget _cell(String text, pw.TextStyle style) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
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
