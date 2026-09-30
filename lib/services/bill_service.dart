import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'logger_service.dart';

class BillService {
  static const String _defaultGeminiApiKey =
      String.fromEnvironment('GEMINI_API_KEY');
  final String _apiKey;

  BillService({String? apiKey}) : _apiKey = apiKey ?? _defaultGeminiApiKey;

  static const String _geminiModel = 'gemini-2.5-flash';
  static const String _fallbackBaseUrl = 'https://shaire-backend.vercel.app';

  static const String _receiptPrompt = '''
You are an expert at extracting information from receipts and bills.
Analyze the provided image and extract the following information:
- Merchant name (restaurant or store name)
- Date of purchase (YYYY-MM-DD format)
- Total amount
- All items purchased with their individual amounts and types

Return the information in a JSON format with the following structure:
{
  "merchant_name": "RESTAURANT NAME",
  "date": "YYYY-MM-DD",
  "total_amount": 45.67,
  "items": [
    {
      "description": "Item name",
      "amount": 12.99,
      "type": "item"
    },
    {
      "description": "Tax",
      "amount": 1.99,
      "type": "tax"
    },
    {
      "description": "Discount",
      "amount": 2.50,
      "type": "discount"
    }
  ]
}

For the "type" field, use one of the following values:
- "item": For regular menu items or products
- "tax": For tax charges or all other additional fees like service fees
- "discount": For discounts or promotions (use positive amounts even for discounts)

If you cannot find some information, use null or empty values. Output ONLY valid JSON.
Ensure the JSON is valid and can be parsed by a computer.
''';

  /// Extracts structured bill data directly from the image using Google Gemini API.
  /// Falls back to the backend service if direct API call is unavailable or fails.
  Future<Map<String, dynamic>> extractBillInfo(File imageFile) async {
    // 1. Try direct Google Gemini API call first for minimal latency
    if (_apiKey.isNotEmpty) {
      try {
        LoggerService.info('Extracting bill via direct Gemini API ($_geminiModel)...');
        final bytes = await imageFile.readAsBytes();
        final base64Image = base64Encode(bytes);

        final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$_geminiModel:generateContent?key=$_apiKey',
        );

        final payload = {
          'contents': [
            {
              'parts': [
                {'text': _receiptPrompt},
                {
                  'inline_data': {
                    'mime_type': 'image/jpeg',
                    'data': base64Image,
                  }
                }
              ]
            }
          ],
          'generationConfig': {
            'responseMimeType': 'application/json',
          }
        };

        final response = await http
            .post(
              url,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 40));

        if (response.statusCode == 200) {
          final responseBody = jsonDecode(response.body);
          final candidates = responseBody['candidates'] as List?;
          if (candidates != null && candidates.isNotEmpty) {
            final parts = candidates[0]['content']?['parts'] as List?;
            if (parts != null && parts.isNotEmpty) {
              final rawText = parts[0]['text'] as String?;
              if (rawText != null) {
                final cleaned = _cleanJsonString(rawText);
                final parsed = jsonDecode(cleaned);
                if (parsed is Map<String, dynamic>) {
                  LoggerService.info('Gemini direct OCR successful: ${parsed['merchant_name']}');
                  return parsed;
                }
              }
            }
          }
        } else {
          LoggerService.warning(
              'Gemini direct API returned ${response.statusCode}: ${response.body}');
        }
      } catch (geminiError) {
        LoggerService.warning(
            'Gemini direct extraction failed: $geminiError. Falling back to backend server...');
      }
    }

    // 2. Fallback to middleman backend if direct call is disabled or fails
    return _extractBillInfoBackend(imageFile);
  }

  Future<Map<String, dynamic>> _extractBillInfoBackend(File imageFile) async {
    try {
      LoggerService.info('Extracting bill via backend fallback: $_fallbackBaseUrl');
      final request =
          http.MultipartRequest('POST', Uri.parse('$_fallbackBaseUrl/extract_bill'));

      request.files.add(await http.MultipartFile.fromPath(
        'image',
        imageFile.path,
      ));

      final response = await request.send().timeout(const Duration(seconds: 60));
      final responseData =
          await response.stream.bytesToString().timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final decoded = json.decode(responseData);
        if (decoded is Map<String, dynamic> && decoded.containsKey('error')) {
          throw Exception(decoded['error']);
        }
        return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
      } else {
        String errorMsg = 'Failed to extract bill info (HTTP ${response.statusCode})';
        try {
          final errorJson = json.decode(responseData);
          if (errorJson is Map && errorJson.containsKey('detail')) {
            errorMsg = errorJson['detail'].toString();
          } else if (errorJson is Map && errorJson.containsKey('error')) {
            errorMsg = errorJson['error'].toString();
          }
        } catch (_) {}
        throw Exception(errorMsg);
      }
    } catch (e) {
      LoggerService.error('Backend bill extraction failed', e);
      rethrow;
    }
  }

  static String cleanJsonString(String raw) {
    var cleaned = raw.trim();
    if (cleaned.startsWith('```json')) {
      cleaned = cleaned.substring(7);
    } else if (cleaned.startsWith('```')) {
      cleaned = cleaned.substring(3);
    }
    if (cleaned.endsWith('```')) {
      cleaned = cleaned.substring(0, cleaned.length - 3);
    }
    return cleaned.trim();
  }

  String _cleanJsonString(String raw) => cleanJsonString(raw);

  Future<bool> checkServerHealth() async {
    if (_apiKey.isNotEmpty) return true;
    try {
      final response = await http
          .get(Uri.parse('$_fallbackBaseUrl/health'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
