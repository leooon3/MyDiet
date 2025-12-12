import 'dart:convert';
import '../services/api_client.dart';
import '../models/diet_models.dart';

class DietRepository {
  final ApiClient _client = ApiClient();

  Future<DietPlan> uploadDiet(String filePath, {String? fcmToken}) async {
    final Map<String, String> fields = {};
    if (fcmToken != null) {
      fields['fcm_token'] = fcmToken;
    }

    final response = await _client.uploadFile(
      '/upload-diet',
      filePath,
      fields: fields,
    );
    return DietPlan.fromJson(response);
  }

  Future<List<dynamic>> scanReceipt(
    String filePath,
    List<String> allowedFoods,
  ) async {
    // Serialize list to JSON string to send as form field
    final String foodsJson = jsonEncode(allowedFoods);

    final response = await _client.uploadFile(
      '/scan-receipt',
      filePath,
      fields: {'allowed_foods': foodsJson},
    );

    return response as List<dynamic>;
  }
}
