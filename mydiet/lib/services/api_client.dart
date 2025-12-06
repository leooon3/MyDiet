import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/env.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  ApiClient._internal();

  Future<dynamic> uploadFile(String endpoint, String filePath) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${Env.apiUrl}$endpoint'),
      );
      request.files.add(await http.MultipartFile.fromPath('file', filePath));

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return json.decode(utf8.decode(response.bodyBytes));
      } else {
        throw Exception('API Error ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      throw Exception('Network Error: $e');
    }
  }
}
