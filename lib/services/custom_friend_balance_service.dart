import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'logger_service.dart';

class CustomFriendBalanceService {
  static const String _balanceKeyPrefix = 'custom_friend_balance_';
  static const String _expensesKeyPrefix = 'custom_friend_expenses_';

  /// Get pairwise balance for an unlinked custom friend
  static Future<Map<String, double>> getBalance(String customFriendId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_balanceKeyPrefix$customFriendId');
      if (raw == null || raw.isEmpty) {
        return {'youOwe': 0.0, 'youAreOwed': 0.0};
      }
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return {
        'youOwe': (map['youOwe'] as num?)?.toDouble() ?? 0.0,
        'youAreOwed': (map['youAreOwed'] as num?)?.toDouble() ?? 0.0,
      };
    } catch (e) {
      LoggerService.warning('Failed to load custom friend balance: $e');
      return {'youOwe': 0.0, 'youAreOwed': 0.0};
    }
  }

  /// Adjust balance: positive deltaAmount means friend owes you more (or you owe them less).
  /// Negative deltaAmount means you owe friend more (or they owe you less).
  static Future<void> adjustBalance({
    required String customFriendId,
    required double deltaAmount,
  }) async {
    try {
      final current = await getBalance(customFriendId);
      double youOwe = current['youOwe'] ?? 0.0;
      double youAreOwed = current['youAreOwed'] ?? 0.0;

      // Net balance from current user's perspective: net = youAreOwed - youOwe
      double net = youAreOwed - youOwe + deltaAmount;

      if (net >= 0) {
        youAreOwed = net;
        youOwe = 0.0;
      } else {
        youAreOwed = 0.0;
        youOwe = -net;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_balanceKeyPrefix$customFriendId',
        jsonEncode({'youOwe': youOwe, 'youAreOwed': youAreOwed}),
      );
    } catch (e) {
      LoggerService.error('Failed to adjust custom friend balance', e);
    }
  }

  /// Record an expense participation for an unlinked custom friend
  static Future<void> recordParticipation({
    required int expenseId,
    required String customFriendId,
    required String description,
    required double totalAmount,
    required double friendShare,
    required bool paidByYou,
    required DateTime date,
    String? payerId,
    double? paidAmount,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_expensesKeyPrefix$customFriendId';
      final existingRaw = prefs.getString(key);
      List<dynamic> list = [];
      if (existingRaw != null && existingRaw.isNotEmpty) {
        list = jsonDecode(existingRaw) as List<dynamic>;
      }

      final double effectivePaidAmount = paidAmount ??
          (paidByYou
              ? 0.0
              : (payerId != null && payerId == customFriendId
                  ? totalAmount
                  : 0.0));

      list.insert(0, {
        'expense_id': expenseId,
        'description': description,
        'total_amount': totalAmount,
        'friend_share': friendShare,
        'your_share': totalAmount - friendShare,
        'paid_by_you': paidByYou,
        'payer_id': payerId,
        'paid_amount': effectivePaidAmount,
        'date': date.toIso8601String(),
      });

      // Keep last 50 records
      if (list.length > 50) {
        list = list.sublist(0, 50);
      }

      await prefs.setString(key, jsonEncode(list));
    } catch (e) {
      LoggerService.warning('Failed to record custom friend expense: $e');
    }
  }

  /// Get recorded expenses for an unlinked custom friend
  static Future<List<Map<String, dynamic>>> getExpenses(
      String customFriendId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_expensesKeyPrefix$customFriendId');
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Clear all cached data for a custom friend when deleted
  static Future<void> clearFriendData(String customFriendId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_balanceKeyPrefix$customFriendId');
      await prefs.remove('$_expensesKeyPrefix$customFriendId');
      LoggerService.info('Cleared local data for custom friend $customFriendId');
    } catch (e) {
      LoggerService.warning('Failed to clear custom friend data: $e');
    }
  }
}
