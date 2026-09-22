import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../widgets/receipt_scanner_section.dart';

class PdfService {
  /// Generates the bill split PDF bytes
  static Future<Uint8List> generateSplitBillPdf({
    required String title,
    required String? merchantName,
    required DateTime date,
    required double totalAmount,
    required String currencySymbol,
    required String splitType,
    required List<BillEntry> billEntries,
    required List<Map<String, dynamic>> participantShares,
    Uint8List? receiptImageBytes,
  }) async {
    final pdf = pw.Document();

    // Load full logo image if available
    pw.MemoryImage? logoImage;
    try {
      final byteData = await rootBundle.load('assets/images/logo-full.png');
      logoImage = pw.MemoryImage(byteData.buffer.asUint8List());
    } catch (_) {
      try {
        final byteData = await rootBundle.load('assets/images/logo.png');
        logoImage = pw.MemoryImage(byteData.buffer.asUint8List());
      } catch (_) {}
    }

    final dateFormat = DateFormat('dd MMM yyyy, hh:mm a');
    final formattedDate = dateFormat.format(date);

    // Load Unicode font for full currency support (₹, $, €, etc.)
    pw.ThemeData? theme;
    String displayCurrency = currencySymbol;
    try {
      final baseFont = await PdfGoogleFonts.notoSansRegular();
      final boldFont = await PdfGoogleFonts.notoSansBold();
      if (baseFont.fontName.toLowerCase().contains('helvetica')) {
        // Fallback occurred inside PdfGoogleFonts because network was unavailable
        if (currencySymbol == '₹') {
          displayCurrency = 'Rs. ';
        }
      } else {
        theme = pw.ThemeData.withFont(base: baseFont, bold: boldFont);
      }
    } catch (_) {
      if (currencySymbol == '₹') {
        displayCurrency = 'Rs. ';
      }
    }

    // Calculate itemized sums
    final regularItems = billEntries
        .where((e) => e.type == BillEntryType.item)
        .toList();
    final taxItems = billEntries
        .where((e) => e.type == BillEntryType.tax)
        .toList();
    final discountItems = billEntries
        .where((e) => e.type == BillEntryType.discount)
        .toList();

    final subtotal = regularItems.fold<double>(0.0, (sum, i) => sum + i.amount);
    final totalTaxes = taxItems.fold<double>(0.0, (sum, i) => sum + i.amount);
    final totalDiscounts = discountItems.fold<double>(0.0, (sum, i) => sum + i.amount);

    pdf.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            // Header with ShAire Logo
            pw.Center(
              child: pw.Column(
                children: [
                  if (logoImage != null)
                    pw.Container(
                      height: 48,
                      margin: const pw.EdgeInsets.only(bottom: 8),
                      child: pw.Image(logoImage),
                    )
                  else
                    pw.Text(
                      'shaire',
                      style: pw.TextStyle(
                        fontSize: 28,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.teal,
                      ),
                    ),
                  pw.Text(
                    'SPLIT BILL SUMMARY',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 2,
                      color: PdfColors.grey700,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Generated on $formattedDate',
                    style: const pw.TextStyle(
                      fontSize: 9,
                      color: PdfColors.grey600,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 12),
            _buildDashedLine(),
            pw.SizedBox(height: 10),

            // Expense Metadata
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      merchantName != null && merchantName.isNotEmpty
                          ? merchantName
                          : title,
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.black,
                      ),
                    ),
                    if (merchantName != null && merchantName.isNotEmpty && title != merchantName)
                      pw.Text(
                        'Note: $title',
                        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                      ),
                    pw.Text(
                      'Split Mode: ${splitType.toUpperCase()}',
                      style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'TOTAL AMOUNT',
                      style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.grey600),
                    ),
                    pw.Text(
                      '$displayCurrency${totalAmount.toStringAsFixed(2)}',
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.teal800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 12),

            // Itemized Items Table (if any)
            if (billEntries.isNotEmpty) ...[
              _buildDashedLine(),
              pw.SizedBox(height: 8),
              pw.Text(
                'ITEMIZED DETAILS',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 1.2,
                  color: PdfColors.grey800,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Table(
                columnWidths: {
                  0: const pw.FlexColumnWidth(4),
                  1: const pw.FlexColumnWidth(2),
                  2: const pw.FlexColumnWidth(3),
                  3: const pw.FlexColumnWidth(2),
                },
                border: null,
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      _buildTableCell('ITEM', isHeader: true),
                      _buildTableCell('TYPE', isHeader: true),
                      _buildTableCell('ASSIGNED TO', isHeader: true),
                      _buildTableCell('AMOUNT', isHeader: true, alignRight: true),
                    ],
                  ),
                  ...billEntries.map((item) {
                    final assignedText = item.assignedTo.isEmpty
                        ? 'Unassigned'
                        : item.assignedTo.join(', ');
                    String typeLabel = 'Item';
                    if (item.type == BillEntryType.tax) typeLabel = 'Tax/Fee';
                    if (item.type == BillEntryType.discount) typeLabel = 'Discount';

                    return pw.TableRow(
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
                        ),
                      ),
                      children: [
                        _buildTableCell(item.description),
                        _buildTableCell(typeLabel),
                        _buildTableCell(assignedText),
                        _buildTableCell(
                          '${item.type == BillEntryType.discount ? "-" : ""}$displayCurrency${item.amount.toStringAsFixed(2)}',
                          alignRight: true,
                          color: item.type == BillEntryType.discount
                              ? PdfColors.green700
                              : PdfColors.black,
                        ),
                      ],
                    );
                  }),
                ],
              ),
              pw.SizedBox(height: 8),

              // Itemized Summary (Subtotal, Taxes, Discounts)
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Container(
                  width: 220,
                  child: pw.Column(
                    children: [
                      if (regularItems.isNotEmpty)
                        _buildSummaryRow('Subtotal', '$displayCurrency${subtotal.toStringAsFixed(2)}'),
                      if (taxItems.isNotEmpty)
                        _buildSummaryRow('Taxes & Extra Charges', '+$displayCurrency${totalTaxes.toStringAsFixed(2)}'),
                      if (discountItems.isNotEmpty)
                        _buildSummaryRow('Discounts', '-$displayCurrency${totalDiscounts.toStringAsFixed(2)}', color: PdfColors.green700),
                      pw.Divider(color: PdfColors.grey400, thickness: 0.8),
                      _buildSummaryRow(
                        'Total',
                        '$displayCurrency${totalAmount.toStringAsFixed(2)}',
                        isBold: true,
                        fontSize: 12,
                      ),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(height: 12),
            ],

            // Split Breakdown Section
            _buildDashedLine(),
            pw.SizedBox(height: 8),
            pw.Text(
              'WHO PAYS WHAT (SPLIT BREAKDOWN)',
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 1.2,
                color: PdfColors.grey800,
              ),
            ),
            pw.SizedBox(height: 6),

            pw.Table(
              columnWidths: {
                0: const pw.FlexColumnWidth(4),
                1: const pw.FlexColumnWidth(2.5),
                2: const pw.FlexColumnWidth(2.5),
                3: const pw.FlexColumnWidth(3),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _buildTableCell('PARTICIPANT', isHeader: true),
                    _buildTableCell('THEIR SHARE', isHeader: true, alignRight: true),
                    _buildTableCell('THEY PAID', isHeader: true, alignRight: true),
                    _buildTableCell('NET STATUS', isHeader: true, alignRight: true),
                  ],
                ),
                ...participantShares.map((p) {
                  final name = p['name']?.toString() ?? 'Unknown';
                  final share = (p['share'] as num?)?.toDouble() ?? 0.0;
                  final paid = (p['paid'] as num?)?.toDouble() ?? 0.0;
                  final net = paid - share;

                  String netStatus;
                  PdfColor netColor;
                  if (net > 0.01) {
                    netStatus = 'Gets $displayCurrency${net.toStringAsFixed(2)}';
                    netColor = PdfColors.green700;
                  } else if (net < -0.01) {
                    netStatus = 'Owes $displayCurrency${(-net).toStringAsFixed(2)}';
                    netColor = PdfColors.red700;
                  } else {
                    netStatus = 'Settled';
                    netColor = PdfColors.grey700;
                  }

                  return pw.TableRow(
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(
                        bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
                      ),
                    ),
                    children: [
                      _buildTableCell(name, isBold: name.toLowerCase() == 'you'),
                      _buildTableCell('$displayCurrency${share.toStringAsFixed(2)}', alignRight: true),
                      _buildTableCell('$displayCurrency${paid.toStringAsFixed(2)}', alignRight: true),
                      _buildTableCell(netStatus, alignRight: true, color: netColor, isBold: true),
                    ],
                  );
                }),
              ],
            ),

            // Attached Original Receipt / Bill Image (if present)
            if (receiptImageBytes != null) ...[
              pw.SizedBox(height: 16),
              _buildDashedLine(),
              pw.SizedBox(height: 8),
              pw.Text(
                'ATTACHED ORIGINAL RECEIPT / BILL',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 1.2,
                  color: PdfColors.grey800,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Center(
                child: pw.Container(
                  constraints: const pw.BoxConstraints(maxHeight: 380),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey400, width: 0.8),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                  ),
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Image(
                    pw.MemoryImage(receiptImageBytes),
                    fit: pw.BoxFit.contain,
                  ),
                ),
              ),
            ],

            pw.SizedBox(height: 20),
            _buildDashedLine(),
            pw.SizedBox(height: 12),

            // Receipt Footer
            pw.Center(
              child: pw.Column(
                children: [
                  pw.Text(
                    'Thank you for using shaire!',
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.teal900,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Split expenses effortlessly - Keep track of friends and groups',
                    style: const pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey600,
                    ),
                  ),
                ],
              ),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  /// Direct trigger to preview, save, or download the PDF
  static Future<void> downloadOrPrintPdf({
    required String title,
    required String? merchantName,
    required DateTime date,
    required double totalAmount,
    required String currencySymbol,
    required String splitType,
    required List<BillEntry> billEntries,
    required List<Map<String, dynamic>> participantShares,
    Uint8List? receiptImageBytes,
  }) async {
    final pdfBytes = await generateSplitBillPdf(
      title: title,
      merchantName: merchantName,
      date: date,
      totalAmount: totalAmount,
      currencySymbol: currencySymbol,
      splitType: splitType,
      billEntries: billEntries,
      participantShares: participantShares,
      receiptImageBytes: receiptImageBytes,
    );

    final safeName = (merchantName ?? title)
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    final filename = 'shaire_split_${safeName.isEmpty ? "bill" : safeName}.pdf';

    await Printing.layoutPdf(
      name: filename,
      onLayout: (PdfPageFormat format) async => pdfBytes,
    );
  }

  static pw.Widget _buildTableCell(
    String text, {
    bool isHeader = false,
    bool isBold = false,
    bool alignRight = false,
    PdfColor color = PdfColors.black,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Align(
        alignment: alignRight ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: isHeader ? 8.5 : 8.5,
            fontWeight: isHeader || isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: isHeader ? PdfColors.grey800 : color,
          ),
        ),
      ),
    );
  }

  static pw.Widget _buildSummaryRow(
    String label,
    String value, {
    bool isBold = false,
    double fontSize = 9,
    PdfColor color = PdfColors.black,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: fontSize,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: PdfColors.grey700,
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: fontSize,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildDashedLine() {
    return pw.LayoutBuilder(
      builder: (context, constraints) {
        final boxWidth = constraints?.maxWidth ?? 500;
        const dashWidth = 4.0;
        const dashSpace = 3.0;
        final dashCount = (boxWidth / (dashWidth + dashSpace)).floor();
        return pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: List.generate(dashCount, (_) {
            return pw.SizedBox(
              width: dashWidth,
              height: 1,
              child: pw.DecoratedBox(
                decoration: const pw.BoxDecoration(color: PdfColors.grey400),
              ),
            );
          }),
        );
      },
    );
  }
}
