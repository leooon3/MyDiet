import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import '../core/env.dart';

class ApiException implements Exception {
  final String message;
  final int statusCode;
  ApiException(this.message, this.statusCode);
  @override
  String toString() => 'ApiException: $message (Code: $statusCode)';
}

class NetworkException implements Exception {
  final String message;
  NetworkException(this.message);
  @override
  String toString() => 'NetworkException: $message';
}

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  ApiClient._internal();

  Future<dynamic> uploadFile(
    String endpoint,
    String filePath, {
    Map<String, String>? fields,
  }) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${Env.apiUrl}$endpoint'),
      );

      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final token = await user.getIdToken(false);
        request.headers['Authorization'] = 'Bearer $token';
      }

      request.files.add(await http.MultipartFile.fromPath('file', filePath));

      if (fields != null) {
        request.fields.addAll(fields);
      }

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      // [FIX] Safe decoding to handle non-JSON errors (like Nginx 500 HTML)
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (response.body.isEmpty) return {};
        try {
          return json.decode(utf8.decode(response.bodyBytes));
        } catch (e) {
          throw ApiException(
            "Invalid JSON response from server",
            response.statusCode,
          );
        }
      } else {
        // [FIX] Truncate error message if it's too long (e.g. HTML dump)
        String errorMsg = response.body;
        if (errorMsg.length > 200) {
          errorMsg = errorMsg.substring(0, 200) + "...";
        }
        throw ApiException('Server error: $errorMsg', response.statusCode);
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw NetworkException('Network error: $e');
    }
  }
}
