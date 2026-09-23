// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaire/services/pdf_service.dart';
import 'package:shaire/widgets/receipt_scanner_section.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Generate sample split bill PDF to project root', () async {
    // 1. Create a dummy receipt thumbnail image (or read an actual image if exists)
    Uint8List? sampleReceiptImage;
    final candidateImage = File('assets/images/logo.png');
    if (candidateImage.existsSync()) {
      sampleReceiptImage = await candidateImage.readAsBytes();
    }

    // 2. Realistic dummy bill entries (Items, Tax, Discount)
    final billEntries = [
      BillEntry(
        description: 'Wood-fired Truffle Pizza',
        amount: 680.0,
        assignedTo: ['You', 'Alex'],
        type: BillEntryType.item,
      ),
      BillEntry(
        description: 'Tuscan Pasta Primavera',
        amount: 420.0,
        assignedTo: ['Sam', 'Priya'],
        type: BillEntryType.item,
      ),
      BillEntry(
        description: 'Garlic Herb Bread (x2)',
        amount: 180.0,
        assignedTo: ['You', 'Alex', 'Sam', 'Priya'],
        type: BillEntryType.item,
      ),
      BillEntry(
        description: 'Craft Lemonade & Iced Tea',
        amount: 320.0,
        assignedTo: ['Alex', 'Sam'],
        type: BillEntryType.item,
      ),
      BillEntry(
        description: 'GST (5%) & Service Charge',
        amount: 80.0,
        assignedTo: ['You', 'Alex', 'Sam', 'Priya'],
        type: BillEntryType.tax,
      ),
      BillEntry(
        description: 'Happy Hour Promo Discount',
        amount: 150.0,
        assignedTo: ['You', 'Alex', 'Sam', 'Priya'],
        type: BillEntryType.discount,
      ),
    ];

    // 3. Realistic participant breakdown
    // Total bill = 680 + 420 + 180 + 320 + 80 - 150 = 1530.00
    // "You" paid the entire bill of 1530.00
    final participantShares = [
      {
        'name': 'You',
        'share': 367.50,
        'paid': 1530.00,
      },
      {
        'name': 'Alex',
        'share': 547.50,
        'paid': 0.0,
      },
      {
        'name': 'Sam',
        'share': 412.50,
        'paid': 0.0,
      },
      {
        'name': 'Priya',
        'share': 202.50,
        'paid': 0.0,
      },
    ];

    print('Generating sample PDF with PdfService...');
    final pdfBytes = await PdfService.generateSplitBillPdf(
      title: 'Weekend Brunch with Friends',
      merchantName: "Luigi's Italian Kitchen",
      date: DateTime.now(),
      totalAmount: 1530.0,
      currencySymbol: 'Rs. ',
      splitType: 'exact',
      billEntries: billEntries,
      participantShares: participantShares,
      receiptImageBytes: sampleReceiptImage,
    );

    // 4. Save to disk in project directory
    final outputFile = File('sample_split_bill.pdf');
    await outputFile.writeAsBytes(pdfBytes);

    print('\n SUCCESS! Sample PDF generated at:');
    print('   -> ${outputFile.absolute.path}');
    print('   -> Size: ${(pdfBytes.length / 1024).toStringAsFixed(1)} KB\n');

    expect(outputFile.existsSync(), isTrue);
    expect(pdfBytes.length, greaterThan(1000));
  });
}
