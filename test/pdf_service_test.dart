import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shaire/services/pdf_service.dart';
import 'package:shaire/widgets/receipt_scanner_section.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PdfService generates split bill PDF with items and bill image', () async {
    final entries = [
      BillEntry(
        description: 'Pizza Margherita',
        amount: 450.0,
        assignedTo: ['You', 'Alex'],
        type: BillEntryType.item,
      ),
      BillEntry(
        description: 'Garlic Bread',
        amount: 150.0,
        assignedTo: ['Alex'],
        type: BillEntryType.item,
      ),
      BillEntry(
        description: 'GST (5%)',
        amount: 30.0,
        assignedTo: ['You', 'Alex'],
        type: BillEntryType.tax,
      ),
      BillEntry(
        description: 'Promo Discount',
        amount: 50.0,
        assignedTo: ['You', 'Alex'],
        type: BillEntryType.discount,
      ),
    ];

    final participants = [
      {'name': 'You', 'share': 265.0, 'paid': 580.0},
      {'name': 'Alex', 'share': 315.0, 'paid': 0.0},
    ];

    // Dummy 1x1 image bytes
    final dummyImageBytes = Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
      0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
      0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
    ]);

    final pdfBytes = await PdfService.generateSplitBillPdf(
      title: 'Dinner at Italian Trattoria',
      merchantName: 'Italian Trattoria',
      date: DateTime.now(),
      totalAmount: 580.0,
      currencySymbol: '₹',
      splitType: 'exact',
      billEntries: entries,
      participantShares: participants,
      receiptImageBytes: dummyImageBytes,
    );

    expect(pdfBytes, isNotNull);
    expect(pdfBytes.length, greaterThan(100));
    // PDF header is '%PDF-'
    final header = String.fromCharCodes(pdfBytes.take(5));
    expect(header, equals('%PDF-'));
  });

  test('logo-full-dark.svg renders cleanly in pw.SvgImage', () async {
    final file = File('assets/images/logo-full-dark.svg');
    expect(file.existsSync(), isTrue);
    final svgContent = await file.readAsString();

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        build: (context) => pw.Center(
          child: pw.Container(
            height: 50,
            child: pw.SvgImage(svg: svgContent),
          ),
        ),
      ),
    );

    final bytes = await doc.save();
    expect(bytes, isNotNull);
    expect(bytes.length, greaterThan(100));
  });

  test('PdfService correctly accepts custom payerName and sanitizes participants', () async {
    final entries = [
      BillEntry(
        description: 'Tacos',
        amount: 200.0,
        assignedTo: ['You', 'Bob'],
        type: BillEntryType.item,
      ),
    ];

    final participants = [
      {'name': 'Rishi', 'share': 100.0, 'paid': 0.0},
      {'name': 'Bob', 'share': 100.0, 'paid': 200.0},
    ];

    final pdfBytes = await PdfService.generateSplitBillPdf(
      title: 'Lunch at Taqueria',
      merchantName: 'Taqueria',
      date: DateTime.now(),
      totalAmount: 200.0,
      currencySymbol: '₹',
      splitType: 'equal',
      billEntries: entries,
      participantShares: participants,
      payerName: 'Bob',
    );

    expect(pdfBytes, isNotNull);
    expect(pdfBytes.length, greaterThan(100));
    final header = String.fromCharCodes(pdfBytes.take(5));
    expect(header, equals('%PDF-'));
  });
}

