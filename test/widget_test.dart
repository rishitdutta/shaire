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
import 'package:shaire/widgets/split_options_widget.dart';
import 'package:shaire/database/expense.dart';
import 'package:shaire/screens/expense_details_screen.dart';

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

  testWidgets('SplitOptionsWidget displays (paid) dynamically based on payerId', (WidgetTester tester) async {
    final contacts = [
      {'id': '101', 'name': 'Bob', 'isGroup': false},
    ];
    final totalAmountCtrl = TextEditingController(text: '100.00');
    final amountCtrls = <String, TextEditingController>{};
    final percentCtrls = <String, TextEditingController>{};

    // 1. Test when You is the payer
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => CurrencyProvider(),
        child: MaterialApp(
          home: DefaultTabController(
            length: 3,
            child: Builder(
              builder: (context) {
                return Scaffold(
                  body: SplitOptionsWidget(
                    tabController: DefaultTabController.of(context),
                    splitType: SplitType.equal,
                    selectedContacts: contacts,
                    totalAmountController: totalAmountCtrl,
                    individualAmountControllers: amountCtrls,
                    individualPercentControllers: percentCtrls,
                    payerId: 'you',
                    onSplitTypeChanged: (_) {},
                    onAmountsChanged: () {},
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('You (paid)'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Bob (paid)'), findsNothing);

    // 2. Test when Bob is the payer
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => CurrencyProvider(),
        child: MaterialApp(
          home: DefaultTabController(
            length: 3,
            child: Builder(
              builder: (context) {
                return Scaffold(
                  body: SplitOptionsWidget(
                    tabController: DefaultTabController.of(context),
                    splitType: SplitType.equal,
                    selectedContacts: contacts,
                    totalAmountController: totalAmountCtrl,
                    individualAmountControllers: amountCtrls,
                    individualPercentControllers: percentCtrls,
                    payerId: '101',
                    onSplitTypeChanged: (_) {},
                    onAmountsChanged: () {},
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('You (paid)'), findsNothing);
    expect(find.text('You'), findsOneWidget);
    expect(find.text('Bob (paid)'), findsOneWidget);
  });

  testWidgets('ReceiptScannerSection does not render redundant Download PDF button', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => CurrencyProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: ReceiptScannerSection(
              billEntries: [
                BillEntry(
                  description: 'Cold Coffee',
                  amount: 150.0,
                  assignedTo: ['You'],
                ),
              ],
              onBatchAssign: () {},
              onEditItem: (_, __) {},
            ),
          ),
        ),
      ),
    );

    // Verify 'Download PDF' button is NOT in ReceiptScannerSection
    expect(find.text('Download PDF'), findsNothing);
  });

  testWidgets('ExpenseDetailsScreen renders details and PDF download button', (WidgetTester tester) async {
    final testExpense = Expense(
      id: 999,
      description: 'Team Dinner',
      totalAmount: 1250.0,
      currency: 'INR',
      date: DateTime(2026, 4, 15, 20, 30),
      createdBy: 'test-user',
      splitType: 'equal',
      categoryId: 1, // Food & Drinks
      createdAt: DateTime(2026, 4, 15),
      updatedAt: DateTime(2026, 4, 15),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => CurrencyProvider(),
        child: MaterialApp(
          home: ExpenseDetailsScreen(expense: testExpense),
        ),
      ),
    );

    // Verify title and details
    expect(find.text('Expense Details'), findsOneWidget);
    expect(find.text('Team Dinner'), findsOneWidget);
    expect(find.text('Food & Drinks'), findsOneWidget);
    expect(find.text('Download Split PDF'), findsOneWidget);
  });
}

