import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/logger_service.dart';

class Balance {
  final int id;
  final String fromUserId;
  final String toUserId;
  final double amount;
  final String currency;
  final int? groupId;
  final DateTime lastUpdated;

  Balance({
    required this.id,
    required this.fromUserId,
    required this.toUserId,
    required this.amount,
    required this.currency,
    this.groupId,
    required this.lastUpdated,
  });

  factory Balance.fromJson(Map<String, dynamic> json) {
    return Balance(
      id: json['id'],
      fromUserId: json['from_user_id'],
      toUserId: json['to_user_id'],
      amount: (json['amount'] as num).toDouble(),
      currency: json['currency'],
      groupId: json['group_id'] as int?,
      lastUpdated: DateTime.parse(json['last_updated']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'from_user_id': fromUserId,
      'to_user_id': toUserId,
      'amount': amount,
      'currency': currency,
      'group_id': groupId,
      'last_updated': lastUpdated.toIso8601String(),
    };
  }
}

class BalanceService {
  final SupabaseClient supabase = Supabase.instance.client;

  /// Fetch a balance by `fromUserId` and `toUserId`
  Future<Balance?> fetchBalance(String fromUserId, String toUserId) async {
    try {
      final response = await supabase
          .from('balances')
          .select('*')
          .eq('from_user_id', fromUserId)
          .eq('to_user_id', toUserId)
          .maybeSingle();

      if (response == null) {
        LoggerService.debug('No balance found between $fromUserId and $toUserId');
        return null;
      }

      return Balance.fromJson(response);
    } catch (error) {
      LoggerService.error('Error fetching balance: $error');
      return null;
    }
  }

  /// Adjust balance between two users by deltaAmount (positive = toUserId owes fromUserId)
  Future<void> adjustBalance({
    required String fromUserId,
    required String toUserId,
    required double deltaAmount,
    required String currency,
    int? groupId,
  }) async {
    if (fromUserId == toUserId || deltaAmount == 0) return;
    try {
      final existing = await supabase
          .from('balances')
          .select('*')
          .or('and(from_user_id.eq.$fromUserId,to_user_id.eq.$toUserId),and(from_user_id.eq.$toUserId,to_user_id.eq.$fromUserId)')
          .maybeSingle();

      if (existing == null) {
        await supabase.from('balances').insert({
          'from_user_id': fromUserId,
          'to_user_id': toUserId,
          'amount': deltaAmount,
          'currency': currency,
          'group_id': groupId,
          'last_updated': DateTime.now().toIso8601String(),
        });
      } else {
        final existingFrom = existing['from_user_id'] as String;
        final currentAmount = (existing['amount'] as num).toDouble();
        final double newAmount = existingFrom == fromUserId
            ? currentAmount + deltaAmount
            : currentAmount - deltaAmount;

        await supabase.from('balances').update({
          'amount': newAmount,
          'last_updated': DateTime.now().toIso8601String(),
        }).eq('id', existing['id']);
      }
    } catch (e) {
      LoggerService.error('Error adjusting balance: $e');
    }
  }

  /// Create a new balance
  Future<bool> createBalance(Balance balance) async {
    try {
      await supabase.from('balances').insert(balance.toJson());
      LoggerService.info('Balance created successfully');
      return true;
    } catch (error) {
      LoggerService.error('Error creating balance: $error');
      return false;
    }
  }

  /// Update an existing balance
  Future<bool> updateBalance(Balance balance) async {
    try {
      await supabase
          .from('balances')
          .update(balance.toJson())
          .eq('id', balance.id);

      LoggerService.info('Balance updated successfully');
      return true;
    } catch (error) {
      LoggerService.error('Error updating balance: $error');
      return false;
    }
  }

  /// Delete a balance by ID
  Future<bool> deleteBalance(int id) async {
    try {
      await supabase.from('balances').delete().eq('id', id);
      LoggerService.info('Balance deleted successfully');
      return true;
    } catch (error) {
      LoggerService.error('Error deleting balance: $error');
      return false;
    }
  }
}

