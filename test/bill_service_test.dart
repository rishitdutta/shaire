import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaire/services/bill_service.dart';
import 'package:image/image.dart' as img;

void main() {
  test('BillService direct Gemini API extraction parses response structure', () async {
    final billService = BillService();

    // Create a small test image with text
    final image = img.Image(width: 200, height: 100);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    img.drawString(image, 'Test Store\nItem 1: \$10.00\nTotal: \$10.00',
        font: img.arial14, x: 10, y: 10, color: img.ColorRgb8(0, 0, 0));

    final tempFile = File('${Directory.systemTemp.path}/test_bill.jpg');
    await tempFile.writeAsBytes(img.encodeJpg(image));

    try {
      final result = await billService.extractBillInfo(tempFile);
      expect(result, isA<Map<String, dynamic>>());
      // Expect either items or merchant_name or total_amount
      expect(result.containsKey('items') || result.containsKey('merchant_name') || result.containsKey('total_amount'), isTrue);
    } finally {
      if (tempFile.existsSync()) {
        tempFile.deleteSync();
      }
    }
  });
}
