import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/env.dart';
import '../models/diet_models.dart';

class DietRepository {
  Future<DietPlan> uploadDiet(String filePath) async {
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('${Env.apiUrl}/upload-diet'),
    );
    request.files.add(await http.MultipartFile.fromPath('file', filePath));

    var streamedResponse = await request.send();
    var response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      return DietPlan.fromJson(json.decode(utf8.decode(response.bodyBytes)));
    } else {
      throw Exception('Failed to upload diet: ${response.body}');
    }
  }

  Future<List<dynamic>> scanReceipt(String filePath) async {
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('${Env.apiUrl}/scan-receipt'),
    );
    request.files.add(await http.MultipartFile.fromPath('file', filePath));

    var streamedResponse = await request.send();
    var response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      return json.decode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('Scan failed');
    }
  }
}
