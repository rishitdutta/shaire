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
import 'package:shaire/screens/auth_screen.dart';
import 'package:shaire/widgets/friend_quick_action_modal.dart';
import 'package:shaire/widgets/edit_tags_dialog.dart';

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

  testWidgets('SplitOptionsWidget displays individual paid amounts when multiple payers exist', (WidgetTester tester) async {
    final contacts = [
      {'id': '101', 'name': 'Bob', 'isGroup': false},
    ];
    final totalAmountCtrl = TextEditingController(text: '100.00');
    final amountCtrls = <String, TextEditingController>{};
    final percentCtrls = <String, TextEditingController>{};

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
                    isMultiplePayers: true,
                    payerAmounts: const {
                      'you': 60.0,
                      '101': 40.0,
                    },
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

    expect(find.text('You (paid ₹60.00)'), findsOneWidget);
    expect(find.text('Bob (paid ₹40.00)'), findsOneWidget);
  });

  testWidgets('AuthScreen shows Forgot Password button in sign in mode and opens reset modal', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AuthScreen(isSignUp: false),
      ),
    );

    // Verify Forgot Password button is present
    expect(find.text('Forgot Password?'), findsOneWidget);

    // Enter email in login screen
    await tester.enterText(find.byType(TextField).first, 'user@example.com');
    await tester.pump();

    // Tap Forgot Password
    await tester.tap(find.text('Forgot Password?'));
    await tester.pumpAndSettle();

    // Bottom sheet should open with prefilled email (present in login field and bottom sheet field)
    expect(find.text('Reset Password'), findsOneWidget);
    expect(find.text('Send Reset Link'), findsOneWidget);
    expect(find.text('user@example.com'), findsNWidgets(2));

    // Switch to code mode
    await tester.tap(find.text('Already have a code? Enter recovery code'));
    await tester.pumpAndSettle();

    expect(find.text('Enter Recovery Code'), findsOneWidget);
    expect(find.text('Update Password'), findsOneWidget);
  });

  testWidgets('AuthScreen hides Forgot Password button in sign up mode', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AuthScreen(isSignUp: true),
      ),
    );

    expect(find.text('Forgot Password?'), findsNothing);
  });

  testWidgets('FriendQuickActionModal renders friend actions, toggle, tags, and updates state', (WidgetTester tester) async {
    final testFriend = {
      'id': 'test-123',
      'full_name': 'Alice Smith',
      'username': 'alice',
      'is_custom': false,
    };

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => CurrencyProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: FriendQuickActionModal(friend: testFriend),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Paid by toggle
    expect(find.text('You'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);

    // Enter amount: 50
    final amountField = find.widgetWithText(TextField, 'Amount');
    await tester.enterText(amountField, '50');
    await tester.pump();

    // Submit button shows Add Expense
    expect(find.text('Add Expense'), findsOneWidget);

    // Verify tags are rendered and tap a tag
    expect(find.text('🍔 Food'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);

    // Verify FilterChip does not show thick checkmark
    final chip = tester.widget<FilterChip>(find.widgetWithText(FilterChip, '🍔 Food'));
    expect(chip.showCheckmark, isFalse);

    await tester.tap(find.text('🍔 Food'));
    await tester.pump();

    // Description should be updated with tag (no "(optional)")
    final descField = find.widgetWithText(TextField, 'Description');
    expect(find.descendant(of: descField, matching: find.text('🍔 Food')), findsOneWidget);
  });

  testWidgets('EditTagsDialog displays tags and allows adding new tags', (WidgetTester tester) async {
    final tags = ['🍔 Food', '☕ Coffee'];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditTagsDialog(initialTags: tags),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Manage Quick Tags'), findsOneWidget);
    expect(find.text('🍔 Food'), findsOneWidget);
    expect(find.text('☕ Coffee'), findsOneWidget);

    // Enter new tag and tap add
    final input = find.byType(TextField);
    await tester.enterText(input, '🍿 Movie');
    await tester.pump();

    await tester.tap(find.byTooltip('Add Tag'));
    await tester.pump();

    expect(find.text('🍿 Movie'), findsOneWidget);
  });
}

