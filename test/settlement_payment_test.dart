import 'package:flutter_test/flutter_test.dart';
import 'package:shaire/database/payment.dart';

/// Regression cover for the settle-up insert.
///
/// `payments.payment_id` is NOT NULL with no database default, so a row that
/// omits it is rejected by Postgres (`23502 null value in column
/// "payment_id"`) and the settlement silently never lands — which is the bug
/// users hit in the field. Every NOT NULL column of that table is pinned
/// here so the payload shape cannot regress again.
void main() {
  const notNullColumns = [
    'payment_id',
    'from_user_id',
    'to_user_id',
    'amount',
    'currency',
    'payment_method',
    'payment_date',
    'status',
  ];

  Map<String, dynamic> row() => PaymentService.buildSettlementRow(
        fromUserId: 'u1',
        toUserId: 'u2',
        amount: 12.5,
        currency: 'INR',
        notes: 'Settlement payment',
      );

  test('carries every NOT NULL payments column', () {
    final r = row();
    for (final column in notNullColumns) {
      expect(r.containsKey(column), isTrue, reason: '$column must be sent');
      expect(r[column], isNotNull, reason: '$column must not be null');
    }
  });

  test('generates a unique, uuid-shaped payment_id per settlement', () {
    final a = row();
    final b = row();
    expect(
        a['payment_id'],
        matches(RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    expect(a['payment_id'], isNot(b['payment_id']));
  });

  test('keeps the fields the balance math and history list read', () {
    final r = PaymentService.buildSettlementRow(
      fromUserId: 'me',
      toUserId: 'friend',
      amount: 99.99,
      currency: 'EUR',
      paymentMethod: 'upi',
      notes: 'Dinner',
    );
    expect(r['amount'], 99.99);
    expect(r['currency'], 'EUR');
    expect(r['payment_method'], 'upi');
    expect(r['status'], 'completed');
    expect(r['notes'], 'Dinner');
    expect(DateTime.tryParse(r['payment_date'] as String), isNotNull);
  });

  test('an explicit payment_id is respected', () {
    final r = PaymentService.buildSettlementRow(
      fromUserId: 'me',
      toUserId: 'friend',
      amount: 1,
      currency: 'INR',
      paymentId: 'fixed-id',
    );
    expect(r['payment_id'], 'fixed-id');
  });
}
