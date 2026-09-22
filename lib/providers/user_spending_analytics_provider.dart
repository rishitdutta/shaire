import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/user_spending_analytics.dart';  // Import the model
import '../services/logger_service.dart';

class AnalyticsProvider with ChangeNotifier {
  final SupabaseClient supabase = Supabase.instance.client;

  List<UserSpendingAnalytics> _analytics = [];
  bool _isLoading = false;

  List<UserSpendingAnalytics> get analytics => _analytics;
  bool get isLoading => _isLoading;

  /// Fetch all spending analytics for a specific user, month, and year
  Future<void> fetchAnalytics(String userId, int month, int year) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await supabase
          .from('user_spending_analytics')
          .select('*')
          .eq('user_id', userId)
          .eq('month', month)
          .eq('year', year)
          .order('updated_at', ascending: false);

      _analytics = response
          .map<UserSpendingAnalytics>(
              (json) => UserSpendingAnalytics.fromJson(json))
          .toList();
    } catch (error) {
      LoggerService.error('Error fetching analytics: $error');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Fetch a single spending analytics record by ID
  Future<UserSpendingAnalytics?> fetchAnalyticsById(int id) async {
    try {
      final response = await supabase
          .from('user_spending_analytics')
          .select('*')
          .eq('id', id)
          .maybeSingle();

      if (response == null) {
        LoggerService.warning('Analytics record not found for ID: $id');
        return null;
      }

      return UserSpendingAnalytics.fromJson(response);
    } catch (error) {
      LoggerService.error('Error fetching analytics by ID: $error');
      return null;
    }
  }

  /// Create a new spending analytics record
  Future<void> createAnalytics(UserSpendingAnalytics analytics) async {
    try {
      await supabase
          .from('user_spending_analytics')
          .insert(analytics.toJson());

      await fetchAnalytics(
        analytics.userId, 
        analytics.month, 
        analytics.year,
      );  // Refresh the list after creation
    } catch (error) {
      LoggerService.error('Error creating analytics: $error');
    }
  }

  /// Update an existing spending analytics record
  Future<void> updateAnalytics(UserSpendingAnalytics analytics) async {
    try {
      await supabase
          .from('user_spending_analytics')
          .update(analytics.toJson())
          .eq('id', analytics.id);

      await fetchAnalytics(
        analytics.userId, 
        analytics.month, 
        analytics.year,
      );  // Refresh the list after update
    } catch (error) {
      LoggerService.error('Error updating analytics: $error');
    }
  }

  /// Delete an analytics record by ID
  Future<void> deleteAnalytics(int id) async {
    try {
      await supabase
          .from('user_spending_analytics')
          .delete()
          .eq('id', id);

      _analytics.removeWhere((analytics) => analytics.id == id);
      notifyListeners();
    } catch (error) {
      LoggerService.error('Error deleting analytics: $error');
    }
  }

  /// Clear all analytics (optional helper)
  void clearAnalytics() {
    _analytics = [];
    notifyListeners();
  }
}
