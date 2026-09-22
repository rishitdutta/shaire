import 'package:flutter/material.dart';
import '../services/prediction_service.dart';
import '../database/expense.dart';
import '../services/logger_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class PredictionProvider with ChangeNotifier {
  bool _isLoading = false;
  bool _hasError = false;
  String _errorMessage = '';
  PredictionResponse? _predictions;
  DateTime? _lastFetchTime;

  bool get needsRefresh {
    if (_lastFetchTime == null) return true;
    final now = DateTime.now();
    // Only refresh predictions if it's been more than 24 hours
    return now.difference(_lastFetchTime!).inHours > 24;
  }

  bool get isLoading => _isLoading;
  bool get hasError => _hasError;
  String get errorMessage => _errorMessage;
  PredictionResponse? get predictions => _predictions;
  double get totalPredictedSpending =>
      _predictions?.totalPredictedSpending ?? 0.0;
  double get averageDailySpending => _predictions?.averageDailySpending ?? 0.0;
  List<DailyPrediction> get dailyPredictions =>
      _predictions?.dailyPredictions ?? [];

  // Get future predictions for next 14 days
  List<DailyPrediction> get futurePredictions {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return dailyPredictions
        .where((prediction) =>
            prediction.date.isAfter(today) &&
            prediction.date.difference(today).inDays <= 14)
        .toList();
  }

  // Load cached predictions
  Future<void> loadCachedPredictions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final predictionsJson = prefs.getString('cached_predictions');
      final lastFetchTime = prefs.getString('predictions_last_fetch');

      if (predictionsJson != null && lastFetchTime != null) {
        final data = jsonDecode(predictionsJson);
        _predictions = PredictionResponse.fromJson(data);
        _lastFetchTime = DateTime.parse(lastFetchTime);
        notifyListeners();
      }
    } catch (e) {
      LoggerService.error('Failed to load cached predictions', e);
      // If loading cache fails, we'll just fetch from API later
    }
  }

  Future<void> _saveToCache() async {
    if (_predictions == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final predictionsJson = jsonEncode({
        'total_predicted_spending': _predictions!.totalPredictedSpending,
        'average_daily_spending': _predictions!.averageDailySpending,
        'daily_predictions': _predictions!.dailyPredictions
            .map((p) => {
                  'date': p.date.toString(),
                  'predicted_amount': p.predictedAmount
                })
            .toList(),
      });

      await prefs.setString('cached_predictions', predictionsJson);
      await prefs.setString(
          'predictions_last_fetch', _lastFetchTime.toString());
    } catch (e) {
      LoggerService.error('Failed to cache predictions', e);
    }
  }

  // Get predictions using past expenses
  Future<void> fetchPredictions(List<Expense> expenses,
      {bool forceRefresh = false}) async {
    // Return cached data if available and not forcing refresh
    if (!forceRefresh && _predictions != null && !needsRefresh) {
      return;
    }

    _isLoading = true;
    _hasError = false;
    _errorMessage = '';
    notifyListeners();

    try {
      if (expenses.isEmpty) {
        // If no past expenses, use the simple prediction with a default amount
        _predictions = await PredictionService.getPredictionsSimple(1500);
      } else {
        // Calculate average daily spending from past expenses
        final now = DateTime.now();
        final oneMonthAgo = DateTime(now.year, now.month - 1, now.day);

        final recentExpenses = expenses
            .where((expense) => expense.date.isAfter(oneMonthAgo))
            .toList();

        double totalSpent =
            recentExpenses.fold(0, (sum, expense) => sum + expense.totalAmount);

        if (recentExpenses.isEmpty) {
          _predictions = await PredictionService.getPredictionsSimple(1500);
        } else {
          double avgDailySpending = totalSpent / 30;

          if (recentExpenses.length < 5) {
            // Not enough data, use simple prediction
            _predictions = await PredictionService.getPredictionsSimple(
                avgDailySpending * 30);
          } else {
            // Enough data, use full prediction model
            _predictions =
                await PredictionService.getPredictions(recentExpenses);
          }
        }
      }

      _lastFetchTime = DateTime.now();
      _isLoading = false;

      // Save to cache
      await _saveToCache();

      notifyListeners();
    } catch (e) {
      LoggerService.error('Error fetching predictions', e);
      _hasError = true;
      _errorMessage = 'Could not reach prediction service. Please pull to refresh to try again.';
      _isLoading = false;
      notifyListeners();
    }
  }
}
