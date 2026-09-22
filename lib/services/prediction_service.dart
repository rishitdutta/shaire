import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:io';
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
  static const Duration _timeout = Duration(seconds: 90);
  static const int _maxRetries = 3;

  static Future<http.Response> _postWithRetry(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
  }) async {
    for (int attempt = 1; attempt <= _maxRetries; attempt++) {
      try {
        LoggerService.info('POST $uri (attempt $attempt/$_maxRetries)');
        final response = await http
            .post(uri, headers: headers, body: body)
            .timeout(_timeout);

        if (response.statusCode == 200) {
          return response;
        }

        if ((response.statusCode == 502 || response.statusCode == 503) &&
            attempt < _maxRetries) {
          LoggerService.warning(
              'Backend waking up (HTTP ${response.statusCode}), retrying in 3s...');
          await Future.delayed(const Duration(seconds: 3));
          continue;
        }

        return response;
      } on SocketException catch (e) {
        LoggerService.warning('Socket error on attempt $attempt: $e');
        if (attempt >= _maxRetries) rethrow;
        await Future.delayed(Duration(seconds: attempt * 2));
      } on http.ClientException catch (e) {
        LoggerService.warning('Client connection error on attempt $attempt: $e');
        if (attempt >= _maxRetries) rethrow;
        await Future.delayed(Duration(seconds: attempt * 2));
      } on TimeoutException catch (e) {
        LoggerService.warning('Request timed out on attempt $attempt: $e');
        if (attempt >= _maxRetries) rethrow;
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }
    throw Exception('Failed to connect to backend after $_maxRetries attempts');
  }

  // Get predictions using simple average spending approach
  static Future<PredictionResponse> getPredictionsSimple(
      double avgSpending) async {
    try {
      final response = await _postWithRetry(
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

      final response = await _postWithRetry(
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
