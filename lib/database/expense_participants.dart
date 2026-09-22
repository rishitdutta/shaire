import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/logger_service.dart';

class ExpenseParticipant {
  final int id;
  final int expenseId;
  final String userId;
  final double shareAmount;
  final double paidAmount;
  final bool settled;

  ExpenseParticipant({
    required this.id,
    required this.expenseId,
    required this.userId,
    required this.shareAmount,
    required this.paidAmount,
    required this.settled,
  });

  factory ExpenseParticipant.fromJson(Map<String, dynamic> json) {
    return ExpenseParticipant(
      id: json['id'],
      expenseId: json['expense_id'],
      userId: json['user_id'],
      shareAmount: (json['share_amount'] as num).toDouble(),
      paidAmount: (json['paid_amount'] as num).toDouble(),
      settled: json['settled'] as bool,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'expense_id': expenseId,
      'user_id': userId,
      'share_amount': shareAmount,
      'paid_amount': paidAmount,
      'settled': settled,
    };
  }
}

class ExpenseParticipantService {
  final SupabaseClient supabase = Supabase.instance.client;

  /// Fetch an expense participant by expense ID and user ID
  Future<ExpenseParticipant?> fetchExpenseParticipant(int expenseId, String userId) async {
    try {
      final response = await supabase
          .from('expense_participants')
          .select('*')
          .eq('expense_id', expenseId)
          .eq('user_id', userId)
          .maybeSingle();

      if (response == null) {
        LoggerService.warning('Expense participant not found');
        return null;
      }

      return ExpenseParticipant.fromJson(response);
    } catch (error) {
      LoggerService.error('Error fetching expense participant: $error');
      return null;
    }
  }

  /// Add a new expense participant
  Future<bool> addExpenseParticipant(ExpenseParticipant participant) async {
    try {
      await supabase.from('expense_participants').insert(participant.toJson());
      LoggerService.info('Expense participant added successfully');
      return true;
    } catch (error) {
      LoggerService.error('Error adding expense participant: $error');
      return false;
    }
  }

  /// Update an existing expense participant
  Future<bool> updateExpenseParticipant(ExpenseParticipant participant) async {
    try {
      await supabase
          .from('expense_participants')
          .update(participant.toJson())
          .eq('id', participant.id);

      LoggerService.info('Expense participant updated successfully');
      return true;
    } catch (error) {
      LoggerService.error('Error updating expense participant: $error');
      return false;
    }
  }

  /// Remove an expense participant by ID
  Future<bool> removeExpenseParticipant(int id) async {
    try {
      await supabase.from('expense_participants').delete().eq('id', id);
      LoggerService.info('Expense participant removed successfully');
      return true;
    } catch (error) {
      LoggerService.error('Error removing expense participant: $error');
      return false;
    }
  }
}
