import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/logger_service.dart';

class UserSpendingAnalytics {
  final int id;
  final String userId;
  final int month;
  final int year;
  final int? categoryId;
  final double totalSpent;
  final double? budgetLimit;
  final DateTime updatedAt;

  UserSpendingAnalytics({
    required this.id,
    required this.userId,
    required this.month,
    required this.year,
    this.categoryId,
    required this.totalSpent,
    this.budgetLimit,
    required this.updatedAt,
  });

  /// Factory constructor to create UserSpendingAnalytics from JSON
  factory UserSpendingAnalytics.fromJson(Map<String, dynamic> json) {
    return UserSpendingAnalytics(
      id: json['id'] as int,
      userId: json['user_id'] as String,
      month: json['month'] as int,
      year: json['year'] as int,
      categoryId: json['category_id'] as int?,
      totalSpent: (json['total_spent'] as num).toDouble(),
      budgetLimit: json['budget_limit'] != null
          ? (json['budget_limit'] as num).toDouble()
          : null,
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  /// Convert UserSpendingAnalytics to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'month': month,
      'year': year,
      'category_id': categoryId,
      'total_spent': totalSpent,
      'budget_limit': budgetLimit,
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

class UserSpendingAnalyticsService {
  final SupabaseClient supabase = Supabase.instance.client;

  /// Fetch analytics by user ID, month, and year
  Future<UserSpendingAnalytics?> fetchUserSpendingAnalytics(
      String userId, int month, int year) async {
    try {
      final response = await supabase
          .from('user_spending_analytics')
          .select('*')
          .eq('user_id', userId)
          .eq('month', month)
          .eq('year', year)
          .maybeSingle();

      if (response == null) {
        LoggerService.warning('No analytics found for user: $userId, month: $month, year: $year');
        return null;
      }

      return UserSpendingAnalytics.fromJson(response);
    } catch (error) {
      LoggerService.error('Error fetching analytics: $error');
      return null;
    }
  }

  /// Create a new spending analytics record
  Future<bool> createUserSpendingAnalytics(
      UserSpendingAnalytics analytics) async {
    try {
      await supabase
          .from('user_spending_analytics')
          .insert(analytics.toJson());

      LoggerService.info('User spending analytics created successfully');
      return true;
    } catch (error) {
      LoggerService.error('Error creating user spending analytics: $error');
      return false;
    }
  }

  /// Update an existing spending analytics record
  Future<bool> updateUserSpendingAnalytics(
      UserSpendingAnalytics analytics) async {
    try {
      await supabase
          .from('user_spending_analytics')
          .update(analytics.toJson())
          .eq('id', analytics.id);

      LoggerService.info('User spending analytics updated successfully');
      return true;
    } catch (error) {
      LoggerService.error('Error updating user spending analytics: $error');
      return false;
    }
  }

  /// Delete a spending analytics record by ID
  Future<bool> deleteUserSpendingAnalytics(int id) async {
    try {
      await supabase
          .from('user_spending_analytics')
          .delete()
          .eq('id', id);

      LoggerService.info('User spending analytics deleted successfully');
      return true;
    } catch (error) {
      LoggerService.error('Error deleting user spending analytics: $error');
      return false;
    }
  }
}
