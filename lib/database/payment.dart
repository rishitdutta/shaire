import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../services/logger_service.dart';

class Payment {
  final int id;
  final String paymentId;
  final String fromUserId;
  final String toUserId;
  final double amount;
  final String currency;
  final String paymentMethod;
  final DateTime paymentDate;
  final String? notes;
  final String status;
  final DateTime createdAt;

  Payment({
    required this.id,
    required this.paymentId,
    required this.fromUserId,
    required this.toUserId,
    required this.amount,
    required this.currency,
    required this.paymentMethod,
    required this.paymentDate,
    this.notes,
    required this.status,
    required this.createdAt,
  });

  factory Payment.fromJson(Map<String, dynamic> json) {
    return Payment(
      id: json['id'],
      paymentId: json['payment_id'],
      fromUserId: json['from_user_id'],
      toUserId: json['to_user_id'],
      amount: (json['amount'] as num).toDouble(), // Ensure double conversion
      currency: json['currency'],
      paymentMethod: json['payment_method'],
      paymentDate: DateTime.parse(json['payment_date']),
      notes: json['notes'],
      status: json['status'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'payment_id': paymentId,
      'from_user_id': fromUserId,
      'to_user_id': toUserId,
      'amount': amount,
      'currency': currency,
      'payment_method': paymentMethod,
      'payment_date': paymentDate.toIso8601String(),
      'notes': notes,
      'status': status,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class PaymentService {
  final SupabaseClient supabase = Supabase.instance.client;

  /// Fetch a payment by ID
  Future<Payment?> fetchPayment(int id) async {
    try {
      final response = await supabase
          .from('payments')
          .select('*')
          .eq('id', id)
          .maybeSingle();

      if (response == null) {
        LoggerService.warning('Payment not found');
        return null;
      }

      return Payment.fromJson(response);
    } catch (error) {
      LoggerService.error('Error fetching payment: $error');
      return null;
    }
  }

  /// Create a new payment
  Future<bool> createPayment(Payment payment) async {
    try {
      await supabase.from('payments').insert(payment.toJson());
      LoggerService.info('Payment created successfully');
      return true;
    } catch (error) {
      LoggerService.error('Error creating payment: $error');
      return false;
    }
  }

  /// Update an existing payment
  Future<bool> updatePayment(Payment payment) async {
    try {
      await supabase
          .from('payments')
          .update(payment.toJson())
          .eq('id', payment.id);

      LoggerService.info('Payment updated successfully');
      return true;
    } catch (error) {
      LoggerService.error('Error updating payment: $error');
      return false;
    }
  }

  /// Fetch all payments between two users ordered by payment_date descending
  Future<List<Map<String, dynamic>>> fetchPaymentsBetweenUsers(
      String user1, String user2) async {
    try {
      final res = await supabase
          .from('payments')
          .select('*')
          .or('and(from_user_id.eq.$user1,to_user_id.eq.$user2),and(from_user_id.eq.$user2,to_user_id.eq.$user1)')
          .order('payment_date', ascending: false);
      return List<Map<String, dynamic>>.from(res);
    } catch (error) {
      LoggerService.error('Error fetching payments between users: $error');
      return [];
    }
  }

  /// Builds the `payments` row for a settlement.
  ///
  /// Separate from [createPaymentRecord] (and covered by
  /// `test/settlement_payment_test.dart`) because every NOT NULL column of
  /// `payments` has to be present: `payment_id` has no database default, and
  /// a row without it dies with `23502 null value in column "payment_id"`,
  /// which is exactly how settle-up used to fail in the field.
  static Map<String, dynamic> buildSettlementRow({
    required String fromUserId,
    required String toUserId,
    required double amount,
    required String currency,
    String paymentMethod = 'manual',
    String? notes,
    String? paymentId,
  }) {
    return {
      'payment_id': paymentId ?? const Uuid().v4(),
      'from_user_id': fromUserId,
      'to_user_id': toUserId,
      'amount': amount,
      'currency': currency,
      'payment_method': paymentMethod,
      'payment_date': DateTime.now().toIso8601String(),
      'status': 'completed',
      'notes': notes,
    };
  }

  /// Create a payment record directly.
  ///
  /// Throws on failure: a settle-up that silently no-ops is worse than an
  /// error the user can see and retry (the old version logged and returned
  /// false, and callers ignored the flag).
  Future<void> createPaymentRecord({
    required String fromUserId,
    required String toUserId,
    required double amount,
    required String currency,
    String paymentMethod = 'manual',
    String? notes,
  }) async {
    await supabase.from('payments').insert(buildSettlementRow(
          fromUserId: fromUserId,
          toUserId: toUserId,
          amount: amount,
          currency: currency,
          paymentMethod: paymentMethod,
          notes: notes,
        ));
    LoggerService.info(
        'Payment recorded: $fromUserId -> $toUserId ($amount $currency)');
  }

  /// Delete a payment by ID
  Future<bool> deletePayment(int id) async {
    try {
      await supabase.from('payments').delete().eq('id', id);
      LoggerService.info('Payment deleted successfully');
      return true;
    } catch (error) {
      LoggerService.error('Error deleting payment: $error');
      return false;
    }
  }
}
