import 'package:http/http.dart' as http;
import 'dart:convert';
import '../database/expense.dart';
import 'logger_service.dart';

class PredictionResponse {
  final double totalPredictedSpending;
  final double averageDailySpending;
  final List<DailyPrediction> dailyPredictions;

  PredictionResponse({
    required this.totalPredictedSpending,
    required this.averageDailySpending,
    required this.dailyPredictions,
  });

  factory PredictionResponse.fromJson(Map<String, dynamic> json) {
    return PredictionResponse(
      totalPredictedSpending:
          (json['total_predicted_spending'] as num).toDouble(),
      averageDailySpending: (json['average_daily_spending'] as num).toDouble(),
      dailyPredictions: (json['daily_predictions'] as List)
          .map((prediction) => DailyPrediction.fromJson(prediction))
          .toList(),
    );
  }
}

class DailyPrediction {
  final DateTime date;
  final double predictedAmount;

  DailyPrediction({
    required this.date,
    required this.predictedAmount,
  });

  factory DailyPrediction.fromJson(Map<String, dynamic> json) {
    return DailyPrediction(
      date: DateTime.parse(json['date']),
      predictedAmount: (json['predicted_amount'] as num).toDouble(),
    );
  }
}

class PredictionService {
  static const String _baseUrl =
      'https://shaire-backend-render-python.onrender.com';

  // Get predictions using simple average spending approach
  static Future<PredictionResponse> getPredictionsSimple(
      double avgSpending) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/predict_spending_simple'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'avg_spending': avgSpending, 'prediction_days': 30}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return PredictionResponse.fromJson(data);
      } else {
        LoggerService.error('Failed to get predictions: ${response.body}');
        throw Exception('Failed to get predictions: ${response.statusCode}');
      }
    } catch (e) {
      LoggerService.error('Error in getPredictionsSimple', e);
      throw Exception('Failed to get predictions: $e');
    }
  }

  // Get predictions using past transactions
  static Future<PredictionResponse> getPredictions(
      List<Expense> expenses) async {
    try {
      final transactions = expenses
          .map((expense) => {
                'date': expense.date.toString().substring(0, 10),
                'amount': expense.totalAmount
              })
          .toList();

      final response = await http.post(
        Uri.parse('$_baseUrl/predict_spending'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'transactions': transactions, 'prediction_days': 30}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return PredictionResponse.fromJson(data);
      } else {
        LoggerService.error('Failed to get predictions: ${response.body}');
        throw Exception('Failed to get predictions: ${response.statusCode}');
      }
    } catch (e) {
      LoggerService.error('Error in getPredictions', e);
      throw Exception('Failed to get predictions: $e');
    }
  }
}
