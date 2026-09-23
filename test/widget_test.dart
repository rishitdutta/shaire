// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shaire/providers/currency_provider.dart';
import 'package:shaire/widgets/receipt_scanner_section.dart';

void main() {
  testWidgets('ReceiptScannerSection renders empty and with items', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => CurrencyProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: ReceiptScannerSection(
              billEntries: [],
              onBatchAssign: () {},
              onEditItem: (entry, index) {},
            ),
          ),
        ),
      ),
    );

    // Empty state should render nothing
    expect(find.text('Receipt Items'), findsNothing);

    // Now render with an entry
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => CurrencyProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: ReceiptScannerSection(
              billEntries: [
                BillEntry(
                  description: 'Garlic Naan',
                  amount: 60.0,
                  assignedTo: ['You'],
                  type: BillEntryType.item,
                ),
              ],
              onBatchAssign: () {},
              onEditItem: (entry, index) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Receipt Items'), findsOneWidget);
    expect(find.text('Garlic Naan'), findsOneWidget);
  });
}
