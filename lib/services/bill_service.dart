import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:io';

import 'logger_service.dart';

class BillService {
  final String baseUrl = "https://shaire-backend.vercel.app";

  Future<Map<String, dynamic>> extractBillInfo(File imageFile) async {
    try {
      // Create multipart request
      var request =
          http.MultipartRequest('POST', Uri.parse('$baseUrl/extract_bill'));

      // Add the image file to the request
      request.files.add(await http.MultipartFile.fromPath(
        'image',
        imageFile.path,
      ));

      // Send the request with 90s timeout
      var response = await request.send().timeout(const Duration(seconds: 90));

      // Get the response
      var responseData = await response.stream.bytesToString().timeout(const Duration(seconds: 30));

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
      LoggerService.error('Error extracting bill info', e);
      rethrow;
    }
  }

  // Health check to verify server is running
  Future<bool> checkServerHealth() async {
    try {
      LoggerService.debug('Checking server health at: ${Uri.parse('$baseUrl/health')}');
      final response = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 10)); // Add timeout
      LoggerService.debug(
          'Server health response: ${response.statusCode}, Body: ${response.body}');
      return response.statusCode == 200;
    } catch (e) {
      LoggerService.error('Server health check failed with error: $e');
      return false;
    }
  }
}
